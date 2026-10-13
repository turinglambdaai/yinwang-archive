#lang racket/base

;; Page templates — a port of src/site/*.njk. The browser-side JS
;; (progress bar, lightbox, TOC, search) is thin UI and is kept verbatim;
;; highlight.js runs client-side from the vendored bundle.

(require racket/string
         racket/list
         racket/match
         racket/format
         racket/dict
         json
         "util.rkt"
         "render.rkt")

(provide (all-defined-out))

;; ---- constants (adsense / umami, from base.njk) ----

(define adsense-client "ca-pub-3215512126020129")
(define adsense-slot "7014497615")
(define umami-id "38c4a1f4-0780-448e-a6f3-2e614c245585")

(define default-description
  "王垠博客文章备份与检索，自动同步 yinwang.org，版权归原作者所有")

;; ---- shared snippets ----

(define (ad-ins)
  (format "    <ins class=\"adsbygoogle\"\n      style=\"display:block\"\n      data-ad-client=\"~a\"\n      data-ad-slot=\"~a\"\n      data-ad-format=\"auto\"\n      data-full-width-responsive=\"true\"></ins>\n      <script>(adsbygoogle = window.adsbygoogle || []).push({});</script>"
          adsense-client adsense-slot))

(define ad-aside-template
  (string-append
   "    <aside class=\"ad-sidebar ad-sidebar--left\">\n"
   (ad-ins) "\n"
   "    </aside>\n"))

(define ad-mobile-template
  (string-append
   "      <div class=\"ad-mobile\">\n"
   (ad-ins) "\n"
   "      </div>\n"))

;; ---- the two inline script blocks (verbatim from base.njk) ----

(define progress-lightbox-toc-script
  #<<SCRIPT
<script>
(function(){
  /* ---- reading progress bar ---- */
  var bar=document.getElementById('reading-progress');
  var article=document.querySelector('.post');
  if(bar&&article){
    var ticking=false;
    var update=function(){
      var r=article.getBoundingClientRect();
      var total=r.height-window.innerHeight;
      var passed=Math.min(Math.max(-r.top,0),Math.max(total,1));
      bar.style.width=(total>0?passed/total*100:100)+'%';
      ticking=false;
    };
    window.addEventListener('scroll',function(){if(!ticking){requestAnimationFrame(update);ticking=true;}},{passive:true});
    window.addEventListener('resize',update,{passive:true});
    update();
  }

  /* ---- images: lazy load + lightbox ---- */
  var lb=document.getElementById('lightbox');
  if(lb){
    var lbImg=lb.querySelector('img');
    var closeLb=function(){lb.classList.remove('active');lbImg.src='';lb.setAttribute('aria-hidden','true');document.body.style.overflow='';};
    document.querySelectorAll('.post-content img').forEach(function(img){
      img.loading='lazy';img.decoding='async';
      img.addEventListener('click',function(){
        lbImg.src=img.currentSrc||img.src;lbImg.alt=img.alt||'';
        lb.classList.add('active');lb.setAttribute('aria-hidden','false');
        document.body.style.overflow='hidden';
      });
    });
    lb.addEventListener('click',closeLb);
    document.addEventListener('keydown',function(e){if(e.key==='Escape'&&lb.classList.contains('active'))closeLb();});
  }

  /* ---- post TOC (progressive enhancement, built from anchored h2/h3) ---- */
  var content=document.querySelector('.post-content');
  if(content){
    var heads=content.querySelectorAll('h2[id],h3[id]');
    if(heads.length>=3){
      var toc=document.createElement('details');
      toc.className='post-toc';
      var sum=document.createElement('summary');
      sum.textContent='本文目录';
      var list=document.createElement('div');
      list.className='post-toc-list';
      heads.forEach(function(h){
        var a=document.createElement('a');
        a.href='#'+h.id;
        a.textContent=h.textContent;
        a.className='post-toc-'+h.tagName.toLowerCase();
        list.appendChild(a);
      });
      toc.appendChild(sum);toc.appendChild(list);
      content.parentNode.insertBefore(toc,content);
    }
  }

  /* ---- client-side syntax highlighting (vendored highlight.js) ---- */
  window.addEventListener('DOMContentLoaded',function(){
    if(window.hljs){window.hljs.highlightAll();}
  });

  /* ---- arrow keys walk to the previous / next post ---- */
  document.addEventListener('keydown',function(e){
    if(e.defaultPrevented||e.altKey||e.ctrlKey||e.metaKey)return;
    var t=e.target;
    if(t&&(t.tagName==='INPUT'||t.tagName==='TEXTAREA'||t.isContentEditable))return;
    var older=document.querySelector('.post-nav-older');
    var newer=document.querySelector('.post-nav-newer');
    if(e.key==='ArrowLeft'&&older)location.href=older.href;
    if(e.key==='ArrowRight'&&newer)location.href=newer.href;
  });
})();
</script>
SCRIPT
  )

(define search-script
  #<<SCRIPT
<script>
(function(){
  var trigger=document.getElementById('search-trigger');
  var overlay=document.getElementById('search-overlay');
  var backdrop=overlay.querySelector('.search-backdrop');
  var input=document.getElementById('search-input');
  var results=document.getElementById('search-results');
  var searchData=null;

  function open(){overlay.classList.add('active');document.body.style.overflow='hidden';input.focus();}
  function close(){overlay.classList.remove('active');document.body.style.overflow='';input.value='';results.innerHTML='<div class="search-hint">输入关键词开始搜索</div>';}

  trigger.addEventListener('click',open);
  backdrop.addEventListener('click',close);

  document.addEventListener('keydown',function(e){
    if((e.metaKey||e.ctrlKey)&&e.key==='k'){e.preventDefault();overlay.classList.contains('active')?close():open();}
    if(e.key==='Escape'&&overlay.classList.contains('active'))close();
  });

  function load(cb){
    if(searchData){cb();return;}
    fetch('/search.json').then(function(r){return r.json();}).then(function(d){searchData=d;cb();}).catch(function(){results.innerHTML='<div class="search-hint">加载失败，请刷新重试</div>';});
  }

  input.addEventListener('input',function(){
    var q=this.value.trim().toLowerCase();
    if(!q){results.innerHTML='<div class="search-hint">输入关键词开始搜索</div>';return;}
    load(function(){
      var matched=searchData.filter(function(p){return p.title.toLowerCase().indexOf(q)!==-1;});
      if(!matched.length){results.innerHTML='<div class="search-hint">没有找到「'+q.replace(/</g,'&lt;')+'」相关的文章</div>';return;}
      var html='';
      matched.slice(0,15).forEach(function(p){
        var t=p.title.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
        var idx=t.toLowerCase().indexOf(q);
        if(idx!==-1){t=t.substring(0,idx)+'<mark>'+t.substring(idx,idx+q.length)+'</mark>'+t.substring(idx+q.length);}
        html+='<a href="'+p.url+'" class="search-result-item">'
          +'<span class="search-result-title">'+t+'</span>'
          +'<span class="search-result-date">'+p.date+'</span>'
          +'</a>';
      });
      if(matched.length>15)html+='<div class="search-hint">还有 '+(matched.length-15)+' 篇相关文章</div>';
      results.innerHTML=html;
    });
  });
})();
</script>
SCRIPT
  )

(define site-logo-svg
  "<svg viewBox=\"0 0 24 24\"><path d=\"M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 2c1.85 0 3.55.63 4.9 1.69L14.3 8.8a4.97 4.97 0 0 0-4.6 0L7.1 5.69A7.96 7.96 0 0 1 12 4zM4 12c0-1.85.63-3.55 1.69-4.9L8.8 9.7a4.97 4.97 0 0 0 0 4.6l-3.11 2.6A7.96 7.96 0 0 1 4 12zm8 8c-1.85 0-3.55-.63-4.9-1.69l2.6-3.11a4.97 4.97 0 0 0 4.6 0l2.6 3.11A7.96 7.96 0 0 1 12 20zm6.31-3.1L15.2 14.3a4.97 4.97 0 0 0 0-4.6l3.11-2.6A7.96 7.96 0 0 1 20 12c0 1.85-.63 3.55-1.69 4.9z\"/></svg>")

;; ---- base layout (base.njk) ----

;; title: page title string or #f; description: meta description or #f;
;; page-url: e.g. "/posts/mites/"; content: rendered HTML.
(define (base-page #:title [title #f]
                   #:description [description #f]
                   #:og-type [og-type #f]
                   #:created [created #f]
                   #:compact-header [compact-header #f]
                   #:page-url page-url
                   content)
  (define full-title
    (if (and title (non-empty-string? title))
        (format "~a - ~a" title site-name)
        site-name))
  (define desc (or description #f))
  (define og-block
    (if desc
        (string-append
         (format "  <meta property=\"og:title\" content=\"~a\">\n" (html-escape-attr full-title))
         (format "  <meta property=\"og:description\" content=\"~a\">\n" (html-escape-attr desc))
         (format "  <meta property=\"og:url\" content=\"~a~a\">\n" site-base-url page-url)
         (format "  <meta property=\"og:type\" content=\"~a\">\n" (or og-type "website"))
         (format "  <meta property=\"og:site_name\" content=\"~a\">\n" (html-escape-attr site-name))
         "  <meta property=\"og:locale\" content=\"zh_CN\">\n"
         "  <meta name=\"twitter:card\" content=\"summary\">\n"
         (if created
             (format "  <meta property=\"article:published_time\" content=\"~a\">\n" (html-escape-attr created))
             ""))
        ""))
  (string-append
   "<!DOCTYPE html>\n"
   (format "<html lang=\"~a\">\n" site-language)
   "<head>\n"
   "  <meta charset=\"UTF-8\">\n"
   "  <link rel=\"icon\" href=\"/favicon.svg\" type=\"image/svg+xml\">\n"
   "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
   (format "  <title>~a</title>\n" (html-escape full-title))
   (format "  <meta name=\"description\" content=\"~a\">\n"
           (html-escape-attr (or desc default-description)))
   og-block
   (format "  <link rel=\"canonical\" href=\"~a~a\">\n" site-base-url page-url)
   (format "  <link rel=\"alternate\" type=\"application/atom+xml\" title=\"~a\" href=\"/feed.xml\">\n"
           (html-escape-attr site-name))
   (format "  <meta name=\"google-adsense-account\" content=\"~a\">\n" adsense-client)
   (format "  <script async src=\"https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=~a\"\n    crossorigin=\"anonymous\"></script>\n" adsense-client)
   (format "  <script defer src=\"https://cloud.umami.is/script.js\" data-website-id=\"~a\"></script>\n" umami-id)
   "  <script defer src=\"/vendor/highlight.min.js\"></script>\n"
   "  <script defer src=\"/vendor/lisp.min.js\"></script>\n"
   "  <script defer src=\"/vendor/scheme.min.js\"></script>\n"
   "  <script defer src=\"/vendor/haskell.min.js\"></script>\n"
   "  <link rel=\"stylesheet\" href=\"/styles/main.css\">\n"
   "</head>\n"
   "<body>\n"
   "  <div class=\"reading-progress\" id=\"reading-progress\" aria-hidden=\"true\"></div>\n"
   "  <div class=\"page-layout\">\n"
   ad-aside-template
   "    <div class=\"page-body\">\n"
   (if compact-header
       (string-append
        "      <header class=\"site-header site-header--compact\">\n"
        "        <div class=\"container\">\n"
        "          <a class=\"site-logo site-logo--compact\" href=\"/\" aria-label=\"返回首页\">" site-logo-svg "</a>\n"
        "          <a class=\"site-title-link\" href=\"/\"><span class=\"site-title\">" (html-escape site-name) "</span></a>\n"
        "        </div>\n"
        "      </header>\n")
       (string-append
        "      <header class=\"site-header\">\n"
        "        <div class=\"container\">\n"
        "          <div class=\"site-logo\" aria-hidden=\"true\">\n"
        "            " site-logo-svg "\n"
        "          </div>\n"
        (format "          <h1 class=\"site-title\">~a</h1>\n" (html-escape site-name))
        "          <p class=\"site-desc\">自动备份 <a href=\"https://www.yinwang.org\">yinwang.org</a> 博客文章</p>\n"
        "        </div>\n"
        "      </header>\n"))
   "      <main class=\"container\">\n"
   content "\n"
   "      </main>\n"
   ad-mobile-template
   "      <footer class=\"site-footer\">\n"
   "        <div class=\"container\">\n"
   "          <p>内容版权归原作者所有 · 本站仅作备份存档</p>\n"
   "          <p class=\"footer-links\">\n"
   "            <a href=\"https://github.com/turinglambdaai/yinwangdl/issues\" target=\"_blank\" rel=\"noopener\">删除请求</a>\n"
   "            <span class=\"sep\">&middot;</span>\n"
   "            <a href=\"/feed.xml\">RSS</a>\n"
   "            <span class=\"sep\">&middot;</span>\n"
   "            <span>站长原创：公众号 <strong>TuringLambdaAI</strong></span>\n"
   "          </p>\n"
   "        </div>\n"
   "      </footer>\n"
   "    </div>\n"
   "    <aside class=\"ad-sidebar ad-sidebar--right\">\n"
   (ad-ins) "\n"
   "    </aside>\n"
   "  </div>\n"
   "\n"
   "<div id=\"search-overlay\" class=\"search-overlay\">\n"
   "  <div class=\"search-backdrop\"></div>\n"
   "  <div class=\"search-dialog\">\n"
   "    <div class=\"search-input-wrap\">\n"
   "      <svg class=\"search-icon\" width=\"20\" height=\"20\" viewBox=\"0 0 20 20\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\"><circle cx=\"8.5\" cy=\"8.5\" r=\"5.5\"/><line x1=\"13\" y1=\"13\" x2=\"18\" y2=\"18\"/></svg>\n"
   "      <input type=\"text\" id=\"search-input\" placeholder=\"搜索文章标题…\" autocomplete=\"off\">\n"
   "      <kbd class=\"search-kbd\">Esc</kbd>\n"
   "    </div>\n"
   "    <div id=\"search-results\" class=\"search-results\">\n"
   "      <div class=\"search-hint\">输入关键词开始搜索</div>\n"
   "    </div>\n"
   "  </div>\n"
   "</div>\n"
   "\n"
   "<div id=\"lightbox\" class=\"lightbox\" aria-hidden=\"true\">\n"
   "  <img alt=\"\">\n"
   "</div>\n"
   "\n"
   "<button id=\"search-trigger\" class=\"search-trigger\" aria-label=\"搜索\">\n"
   "  <svg width=\"18\" height=\"18\" viewBox=\"0 0 20 20\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"2\" stroke-linecap=\"round\"><circle cx=\"8.5\" cy=\"8.5\" r=\"5.5\"/><line x1=\"13\" y1=\"13\" x2=\"18\" y2=\"18\"/></svg>\n"
   "  <span class=\"search-trigger-text\">搜索</span>\n"
   "  <span class=\"search-trigger-tip\">Ctrl K</span>\n"
   "</button>\n"
   "\n"
   progress-lightbox-toc-script "\n\n"
   search-script "\n"
   "</body>\n"
   "</html>\n"))

;; ---- post page (post.njk) ----

;; p is an assoc list with keys title/slug/author/created/source/html/url
;; older/newer: neighbouring post assoc lists or #f.
(define (post-page p older newer)
  (define title (dict-ref p 'title ""))
  (define author (let ([a (dict-ref p 'author "")]) (if (equal? a "") "王垠" a)))
  (define created (dict-ref p 'created #f))
  (define source (dict-ref p 'source #f))
  (define url (dict-ref p 'url))
  (define jsonld
    (format
     "<script type=\"application/ld+json\">\n{\n  \"@context\": \"https://schema.org\",\n  \"@type\": \"Article\",\n  \"headline\": ~a,\n  \"datePublished\": ~a,\n  \"author\": { \"@type\": \"Person\", \"name\": ~a },\n  \"publisher\": { \"@type\": \"Organization\", \"name\": \"王垠博客备份\" },\n  \"mainEntityOfPage\": ~a,\n  \"inLanguage\": \"zh-CN\"\n}\n</script>\n"
     (jsexpr->string title)
     (jsexpr->string (or created ""))
     (jsexpr->string author)
     (jsexpr->string (string-append site-base-url url))))
  (define meta-line
    (string-append
     (format "      <span>~a</span>\n" (html-escape author))
     (if created
         (format "      <span class=\"sep\">&middot;</span>\n      <time>~a</time>\n" (html-escape (isodate created)))
         "")
     (if (and source (non-empty-string? source))
         (format "      <span class=\"sep\">&middot;</span>\n      <a href=\"~a\" target=\"_blank\" rel=\"noopener\">原文</a>\n"
                 (html-escape-attr source))
         "")))
  (define post-nav
    (if (not (or older newer))
        ""
        (string-append
         "  <nav class=\"post-nav\" aria-label=\"文章导航\">\n"
         (if older
             (format "    <a class=\"post-nav-item post-nav-older\" href=\"~a\">\n      <span class=\"post-nav-label\">&larr; 更早一篇</span>\n      <span class=\"post-nav-title\">~a</span>\n    </a>\n"
                     (dict-ref older 'url)
                     (html-escape (dict-ref older 'title "")))
             "")
         (if newer
             (format "    <a class=\"post-nav-item post-nav-newer\" href=\"~a\">\n      <span class=\"post-nav-label\">更新一篇 &rarr;</span>\n      <span class=\"post-nav-title\">~a</span>\n    </a>\n"
                     (dict-ref newer 'url)
                     (html-escape (dict-ref newer 'title "")))
             "")
         "  </nav>\n")))
  (define content
    (string-append
     jsonld
     "<article class=\"post\">\n"
     "  <header class=\"post-header\">\n"
     (format "    <h1>~a</h1>\n" (html-escape title))
     "    <div class=\"post-meta\">\n"
     meta-line
     "    </div>\n"
     "  </header>\n"
     "  <div class=\"post-content\">\n"
     (dict-ref p 'html) "\n"
     "  </div>\n"
     "\n"
     post-nav
     "</article>"))
  (base-page #:title title
             #:description #f
             #:og-type "article"
             #:created created
             #:compact-header #t
             #:page-url url
             content))

;; ---- home page with year sections + pagination (index.njk) ----

;; posts: list of post assoc lists (already sliced for this page)
;; page-number: 0-based; total-pages: for the pagination nav.
(define (index-page posts page-number total-pages)
  ;; njk loop: a year-section div opens at each year change and closes at
  ;; the next change or the end of the page
  (define cards
    (let loop ([ls posts] [current-year "0000"] [open? #f] [acc '()])
      (match ls
        ['() (if open? (cons "      </div>\n" (reverse acc)) (reverse acc))]
        [(cons p rest)
         (define y (year-of (dict-ref p 'created #f)))
         (define (open-section acc2)
           (cons (format "    <div class=\"year-section\">\n      <div class=\"year-label\">~a</div>\n" y) acc2))
         (cond
           [(not (equal? y current-year))
            (let* ([a1 (if open? (cons "      </div>\n" acc) acc)]
                   [a2 (open-section a1)]
                   [a3 (cons (post-card p) a2)])
              (loop rest y #t a3))]
           [else
            (loop rest current-year open? (cons (post-card p) acc))])])))
  (define pagination
    (if (<= total-pages 1)
        ""
        (let ([prev (if (> page-number 0)
                        (format "    <a href=\"~a\" class=\"prev\">&larr; 上一页</a>\n"
                                (page-url (- page-number 1)))
                        "")]
              [next (if (< page-number (- total-pages 1))
                        (format "    <a href=\"~a\" class=\"next\">下一页 &rarr;</a>\n"
                                (page-url (+ page-number 1)))
                        "")])
          (string-append "  <nav class=\"pagination\">\n" prev next "  </nav>\n"))))
  (define content
    (string-append "<div class=\"home\">\n"
                   (string-append* cards)
                   pagination
                   "</div>"))
  (base-page #:title ""
             #:page-url (page-url page-number)
             content))

(define (post-card p)
  (string-append
   "    <div class=\"post-card\">\n"
   "      <div class=\"post-card-title\">\n"
   (format "        <a href=\"~a\">~a</a>\n"
           (dict-ref p 'url) (html-escape (or (dict-ref p 'title #f) (dict-ref p 'slug ""))))
   "      </div>\n"
   (if (dict-ref p 'created #f)
       (format "      <div class=\"post-card-date\">~a</div>\n" (html-escape (isodate (dict-ref p 'created #f))))
       "")
   "    </div>\n"))

;; URL of a 0-based pagination page: "/" for the first, "/page/N/" after.
(define (page-url n)
  (if (zero? n) "/" (format "/page/~a/" (+ n 1))))

;; JSON string helper (njk `| dump | safe`)
(define (jsexpr->string s)
  (jsexpr->python-json s))

;; ---- Atom feed (feed.njk) ----

;; RFC3339 of a "YYYY-MM-DD" date at UTC midnight (dateToRfc3339 parity)
(define (date-rfc3339 created)
  (if created
      (format "~aT00:00:00.000Z" (isodate created))
      (now-iso-utc)))

(define (feed-xml posts)
  ;; posts: full sorted list; newest created date feeds <updated>
  (define newest
    (for/fold ([m #f]) ([p (in-list posts)])
      (define c (dict-ref p 'created #f))
      (if (and c (or (not m) (string>? c m))) c m)))
  (string-append
   "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
   "<feed xmlns=\"http://www.w3.org/2005/Atom\">\n"
   (format "  <title>~a</title>\n" (html-escape site-name))
   "  <subtitle>王垠博客自动备份存档，版权归原作者所有</subtitle>\n"
   (format "  <link href=\"~a/\" />\n" site-base-url)
   (format "  <link rel=\"self\" href=\"~a/feed.xml\" />\n" site-base-url)
   (format "  <updated>~a</updated>\n" (date-rfc3339 newest))
   (format "  <id>~a/</id>\n" site-base-url)
   (string-append*
    (for/list ([p (in-list (take posts (min 20 (length posts))))])
      (define abs-url (format "~a~a" site-base-url (dict-ref p 'url)))
      (string-append
       "  <entry>\n"
       (format "    <title>~a</title>\n" (html-escape (dict-ref p 'title "")))
       (format "    <link href=\"~a\" />\n" abs-url)
       (format "    <published>~a</published>\n" (dict-ref p 'created ""))
       (format "    <updated>~a</updated>\n" (date-rfc3339 (dict-ref p 'created #f)))
       (format "    <id>~a</id>\n" abs-url)
       (format "    <summary>~a</summary>\n"
               (html-escape (excerpt-of (dict-ref p 'html "") 140)))
       "  </entry>\n")))
   "</feed>\n"))

;; ---- search index (search.json.njk) ----

(define (search-json posts)
  (string-append
   "[\n"
   (string-join
    (for/list ([p (in-list posts)])
      (format "  {\n    \"title\": ~a,\n    \"url\": ~a,\n    \"date\": ~a\n  }"
              (jsexpr->python-json (dict-ref p 'title ""))
              (jsexpr->python-json (dict-ref p 'url))
              (jsexpr->python-json (isodate (dict-ref p 'created #f)))))
    ",\n")
   "\n]\n"))

;; ---- sitemap (sitemap.njk) ----

(define (sitemap-xml posts page-count)
  (define urls
    (append
     (list (cons "/" #f))
     (for/list ([n (in-range 1 page-count)])
       (cons (page-url n) #f))
     (for/list ([p (in-list posts)])
       (cons (dict-ref p 'url) (dict-ref p 'created #f)))))
  (string-append
   "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
   "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
   (string-append*
    (for/list ([u (in-list urls)])
      (string-append
       "  <url>\n"
       (format "    <loc>~a~a</loc>\n" site-base-url (car u))
       (if (cdr u)
           (format "    <lastmod>~a</lastmod>\n" (cdr u))
           "")
       "  </url>\n")))
   "</urlset>\n"))

;; ---- llms.txt (llms.njk) ----

(define (llms-txt posts)
  (string-append
   (format "# 王垠博客备份（~a）\n\n" site-name)
   "> 王垠（Yin Wang）博客 yinwang.org 的自动备份存档站。内容版权归原作者所有，本站仅作备份，不销售任何内容。文章为中文，主题涵盖编程语言、Lisp/Scheme、编译器、程序设计思想、人工智能等。\n\n"
   (format "站点：~a\n" site-base-url)
   (format "订阅：~a/feed.xml\n" site-base-url)
   "更新：每周自动同步源站新文章\n\n"
   (format "## 文章索引（~a 篇，按时间倒序）\n" (length posts))
   (string-append*
    (for/list ([p (in-list posts)])
      (format "- [~a](~a~a)（~a）\n"
              (dict-ref p 'title "")
              site-base-url
              (dict-ref p 'url)
              (dict-ref p 'created ""))))))
