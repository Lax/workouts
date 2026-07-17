require "thor"
require "webrick"
require "fileutils"
require "json"

module Workouts
  class ServeCLI < Thor
      desc "start", "Start HTTP upload server for Apple Health export"
      option :port, type: :numeric, default: 8080, aliases: "-p",
             desc: "Port number (env: UPLOAD_PORT)"
      def start
        port = options[:port] || ENV.fetch("UPLOAD_PORT", 8080).to_i
        upload_dir = "data/raw/apple_health"
        target = File.join(upload_dir, "export.zip")
        FileUtils.mkdir_p(upload_dir)

        log = WEBrick::Log.new($stdout, WEBrick::Log::INFO)
        server = WEBrick::HTTPServer.new(
          Port: port, Logger: log,
          AccessLog: [[$stdout, WEBrick::AccessLog::COMMON_LOG_FORMAT]]
        )

        server.mount_proc "/" do |_req, res|
          res.content_type = "text/html; charset=utf-8"
          res.body = PAGE
        end

        server.mount_proc "/upload" do |req, res|
          begin
            unless req.query["file"]&.respond_to?(:filename)
              res.status = 400
              res.content_type = "application/json"
              res.body = JSON.generate({ error: "No file" })
              next
            end

            file = req.query["file"]
            File.binwrite(target, file.to_s)
            size = File.size(target)

            log.info "#{file.filename} (#{size} bytes) → #{target}"
            res.content_type = "application/json"
            res.body = JSON.generate({ ok: true, size: size, path: target })
          rescue => e
            res.status = 500
            res.content_type = "application/json"
            res.body = JSON.generate({ error: e.message })
          end
        end

        %w[INT TERM].each { |sig| trap(sig) { server.shutdown } }
        say "Upload server at http://0.0.0.0:#{port}", :green
        server.start
      end
  end

  PAGE = <<~HTML.freeze
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>Workouts Upload</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;background:#1a1a1a;color:#eee;min-height:100dvh;display:flex;align-items:center;justify-content:center;padding:1rem}
.card{background:#2a2a2a;border-radius:16px;padding:2rem;width:100%;max-width:400px;text-align:center}
.dz{border:2px dashed #555;border-radius:12px;padding:2rem 1rem;margin:1.5rem 0;transition:.2s;cursor:pointer}
.dz.active{border-color:#4caf50;background:#2d3d2d}
.dz.has{border-color:#2196f3}
.dz .ic{font-size:2.5rem;margin-bottom:.5rem}
.dz p{color:#888;font-size:.9rem}
.dz .nm{color:#4caf50;font-size:.85rem;margin-top:.5rem}
.btn{width:100%;padding:.8rem;border:none;border-radius:10px;font-size:1rem;font-weight:600;cursor:pointer;transition:.2s;min-height:48px;touch-action:manipulation}
.btn-up{background:#4caf50;color:#fff}
.btn-up:disabled{background:#3a3a3a;color:#666;cursor:not-allowed}
.btn-up:not(:disabled):active{transform:scale(.97)}
.st{margin-top:1rem;padding:.8rem;border-radius:10px;font-size:.9rem;display:none}
.st.ok{display:block;background:#1b3a1b;color:#4caf50}
.st.er{display:block;background:#3a1b1b;color:#f44336}
.sz{color:#666;font-size:.8rem;margin-top:.3rem}
input[type=file]{display:none}
</style>
</head>
<body>
<div class="card">
<h1>Upload</h1>
<div class="dz" id="dz" role="button" tabindex="0">
<div class="ic">📁</div>
<p id="dt">Tap to select<br>or drag export.zip</p>
<div class="nm" id="fn" style="display:none"></div>
</div>
<input type="file" id="fi" accept=".zip">
<button class="btn btn-up" id="ub" disabled>Upload</button>
<div class="st" id="st"></div>
</div>
<script>
let f=null,z=document.getElementById('dz'),i=document.getElementById('fi'),n=document.getElementById('fn'),t=document.getElementById('dt'),b=document.getElementById('ub'),s=document.getElementById('st')
z.addEventListener('click',()=>i.click())
z.addEventListener('dragover',e=>{e.preventDefault();z.classList.add('active')})
z.addEventListener('dragleave',()=>z.classList.remove('active'))
z.addEventListener('drop',e=>{e.preventDefault();z.classList.remove('active');setF(e.dataTransfer.files[0])})
i.addEventListener('change',()=>setF(i.files[0]))
function setF(x){f=x;if(!x){z.classList.remove('has');n.style.display='none';t.style.display='';b.disabled=true;return}
z.classList.add('has');n.textContent=x.name;n.style.display='';t.style.display='none';b.disabled=false}
b.addEventListener('click',async()=>{if(!f)return;b.disabled=true;b.textContent='Uploading...';s.className='st';s.style.display='none'
const d=new FormData();d.append('file',f)
try{const r=await fetch('/upload',{method:'POST',body:d});const j=await r.json()
if(j.ok){s.className='st ok';s.style.display='block';s.innerHTML='<span style=font-size:1.5rem>✓</span><br>'+(j.size/1048576).toFixed(1)+' MB'}
else throw new Error(j.error||'Upload failed')}catch(e){s.className='st er';s.style.display='block';s.textContent='✗ '+e.message}
b.disabled=false;b.textContent='Upload'})
</script>
</body>
</html>
  HTML
end
