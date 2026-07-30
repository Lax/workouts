require "webrick"
require "json"
require "yaml"
require "socket"
require "faraday"
require "uri"

module Workouts
  module Auth
    class Strava
      STATUS_COLORS = {done: 32, warn: 33, error: 31, auth: 36}.freeze

      def initialize(cli_options, config)
        @options = cli_options
        @config = config
      end

      def call
        strava_cfg = @config.sync_config("strava")
        client_id = strava_cfg["client_id"].to_s
        client_secret = strava_cfg["client_secret"].to_s
        creds_missing = client_id.empty? || client_secret.empty?

        if creds_missing
          puts "\e[33m⚠  Strava API credentials not configured — see browser page\e[0m"
        end

        port = TCPServer.open("127.0.0.1", 0) { |s| s.addr[1] }
        redirect_uri = "http://localhost:#{port}/callback"

        code = nil
        exchange_error = nil
        tokens = nil

        log_file = File.open(File::NULL, "w")
        server = WEBrick::HTTPServer.new(
          Port: port, Logger: WEBrick::Log.new(log_file),
          AccessLog: [[log_file, ""]]
        )

        server.mount_proc "/" do |req, res|
          fresh = File.exist?("config/config.yml") ? (YAML.safe_load_file("config/config.yml") || {}) : {}
          scfg = fresh.dig("sync", "strava") || {}
          has_creds = scfg["client_id"].to_s != "" && scfg["client_secret"].to_s != ""

          if has_creds
            auth_url = "https://www.strava.com/oauth/authorize?" + URI.encode_www_form(
              client_id: scfg["client_id"], redirect_uri: redirect_uri,
              response_type: "code", approval_prompt: "force",
              scope: "read_all,profile:read_all,activity:read_all"
            )
            res.body = success_html(auth_url)
          else
            res.body = config_page_html
          end
        end

        server.mount_proc "/callback" do |req, res|
          fresh = File.exist?("config/config.yml") ? (YAML.safe_load_file("config/config.yml") || {}) : {}
          scfg = fresh.dig("sync", "strava") || {}
          cid = scfg["client_id"].to_s
          csec = scfg["client_secret"].to_s

          code = req.query["code"]
          if code && !cid.empty? && !csec.empty? && !code.empty?
            begin
              resp = Faraday.post("https://www.strava.com/oauth/token") do |r|
                r.body = {client_id: cid, client_secret: csec, code: code, grant_type: "authorization_code"}
              end
              if resp.success?
                tokens = JSON.parse(resp.body)
                rt = tokens["refresh_token"]

                config_path = File.expand_path(@options[:config] || "config/config.yml")
                cfg = File.exist?(config_path) ? (YAML.safe_load_file(config_path) || {}) : {}
                cfg["sync"] ||= {}
                cfg["sync"]["strava"] ||= {}
                cfg["sync"]["strava"]["client_id"] ||= cid
                cfg["sync"]["strava"]["client_secret"] ||= csec
                cfg["sync"]["strava"]["refresh_token"] = rt
                File.write(config_path, YAML.dump(cfg))

                puts "\e[32m✓ Strava authorization successful\e[0m"
              else
                exchange_error = "Token exchange failed: HTTP #{resp.status}"
              end
            rescue => e
              exchange_error = e.message
            end
          else
            exchange_error = "No authorization code received"
          end

          if tokens
            repo = `git remote get-url origin 2>/dev/null`.strip.sub(/.*github\.com[\/:]/, "").sub(/\.git$/, "")
            gh_url = repo.empty? ? "https://github.com" : "https://github.com/#{repo}/settings/secrets/actions"
            rt = tokens["refresh_token"]
            config_path = File.expand_path(@options[:config] || "config/config.yml")
            res.body = result_html(cid, csec, rt, gh_url, config_path)
          else
            res.body = "<html><body><h1>#{exchange_error || "Unknown error"}</h1><p>Please close and try again.</p></body></html>"
          end
        end

        server.mount_proc "/shutdown" do |_req, res|
          res.body = "<html><body><h1>Server closed</h1><p>You may close this window.</p></body></html>"
          server.shutdown
        end

        Thread.new { server.start }
        puts "\e[36m🔗  Open in your browser:\e[0m"
        puts "  http://localhost:#{port}"

        begin
          sleep 0.1 while server.status == :Running
        rescue Interrupt
          puts "\e[33m⚠  Server stopped by user\e[0m"
        end

        if exchange_error
          puts "\e[31m✗ #{exchange_error}\e[0m"
          return
        end

        if tokens
          rt = tokens["refresh_token"]
          puts "\e[32m✓ Done\e[0m"
          puts ""
          puts "GitHub Actions Secrets:"
          puts "  SYNC_STRAVA_CLIENT_ID = #{client_id}"
          puts "  SYNC_STRAVA_CLIENT_SECRET = #{client_secret}"
          puts "  SYNC_STRAVA_REFRESH_TOKEN = #{rt}"
          puts ""
          puts "Local config:"
          puts "  strava:"
          puts "    refresh_token: #{rt}"
        end
      end

      private

      def success_html(auth_url)
        <<~HTML
          <!DOCTYPE html><html lang="zh-CN"><head>
          <meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
          <title>Workouts CLI — Strava 授权</title>
          <style>body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#222;color:#eee;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;text-align:center}.card{background:#333;border-radius:12px;padding:3rem 2rem;max-width:520px;box-shadow:0 8px 32px rgba(0,0,0,0.3)}.icon{font-size:2.5rem;margin-bottom:0.5rem}h1{font-size:1.2rem;margin:0 0 0.3rem}p{color:#aaa;margin:0 0 1.5rem;font-size:0.9rem}.badge{display:inline-block;background:#2a2;color:#fff;padding:0.3rem 0.8rem;border-radius:4px;font-size:0.8rem;margin-bottom:1.5rem}.btn{display:inline-block;background:#FC4C02;color:#fff;text-decoration:none;padding:0.8rem 2rem;border-radius:6px;font-weight:600;font-size:1rem;transition:0.2s}.btn:hover{background:#e04400}.hint{color:#666;font-size:0.8rem;margin-top:1.5rem}</style></head><body>
          <div class="card"><div class="icon">🏃</div><h1>Connect with Strava</h1>
          <p>授权 Workouts CLI 同步你的运动数据<br>Authorize Workouts CLI to sync your activities</p>
          <div class="badge">✓ client_id & client_secret 已配置</div><br>
          <a class="btn" href="#{auth_url}">Connect with Strava ↗</a>
          <div class="hint">授权后将自动跳转回此页面</div></div></body></html>
        HTML
      end

      def config_page_html
        <<~HTML
            <!DOCTYPE html><html lang="zh-CN"><head>
            <meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
            <title>Strava 授权 — 配置缺失</title>
            <style>body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#222;color:#eee;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;text-align:left}.card{background:#333;border-radius:12px;padding:2.5rem 2rem;max-width:640px;box-shadow:0 8px 32px rgba(0,0,0,0.3)}h1{color:#FC4C02;font-size:1.1rem;margin:0 0 1rem}ol{color:#aaa;line-height:1.8;padding-left:1.2rem}code{background:#1a1a1a;padding:0.1rem 0.3rem;border-radius:3px}.box{background:#1a1a1a;border-radius:6px;padding:0.8rem;font-family:monospace;font-size:0.8rem;white-space:pre;margin:0.5rem 0}.hint{color:#666;font-size:0.8rem;margin-top:1rem}</style></head><body>
            <div class="card"><h1>⚠ 缺少 Strava API 凭证</h1><p style="color:#aaa;font-size:0.9rem">Missing Strava API credentials</p>
            <ol><li>前往 <a href="https://www.strava.com/settings/api" style="color:#FC4C02">strava.com/settings/api</a></li>
            <li>点击 "Create & Manage Your App"</li>
            <li>填写 Application Name、Website（任意）、Authorization Callback Domain = <code>localhost</code></li>
            <li>复制 Client ID 和 Client Secret</li></ol>
            <p style="color:#aaa;font-size:0.85rem">配置后<b>刷新此页面</b>即可开始授权（无需重启）</p>
            <div class="box"># config/config.yml
          strava:
            client_id: "your_client_id"
            client_secret: "your_client_secret"
            # refresh_token: (由 auth strava 自动填充)</div>
            <div class="hint">配置 config.yml 后刷新此页面</div></div></body></html>
        HTML
      end

      def result_html(cid, csec, rt, gh_url, config_path)
        <<~HTML
            <!DOCTYPE html><html lang="zh-CN"><head>
            <meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
            <title>Workouts CLI — 授权成功</title>
            <style>body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#222;color:#eee;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0}.card{background:#333;border-radius:12px;padding:2.5rem 2rem;max-width:640px;box-shadow:0 8px 32px rgba(0,0,0,0.3);text-align:left}h1{text-align:center;font-size:1.2rem}.section{margin:1.5rem 0}.section h2{font-size:1rem;margin:0 0 0.5rem;color:#FC4C02}.box{background:#1a1a1a;border-radius:6px;padding:0.8rem;font-family:"SFMono-Regular",Consolas,monospace;font-size:0.8rem;position:relative;overflow-x:auto}.box code{display:block;white-space:pre}.copy{cursor:pointer;position:absolute;top:0.4rem;right:0.5rem;background:#555;color:#fff;border:none;border-radius:3px;padding:0.15rem 0.5rem;font-size:0.7rem}.copy:hover{background:#777}.action-btn{display:inline-block;background:#238636;color:#fff;text-decoration:none;padding:0.6rem 1.2rem;border-radius:6px;font-size:0.85rem;margin-top:0.5rem}.action-btn:hover{background:#2ea043}hr{border:none;border-top:1px solid #444;margin:1.2rem 0}</style></head><body>
            <div class="card"><h1>✓ 授权成功<br><span style="font-size:0.8rem;color:#aaa;font-weight:400">Authorization Successful</span></h1>
            <div class="section"><h2>📦 GitHub Actions Secrets</h2>
            <p style="margin:0.3rem 0 0.6rem;font-size:0.8rem;color:#aaa">Settings → Secrets and variables → Actions → New repository secret</p>
            <div class="box"><button class="copy" onclick="cn('n0')">📋 Name</button><button class="copy" style="margin-left:0.3rem" onclick="cv('v0')">📋 Value</button>
            <code>Name:  SYNC_STRAVA_CLIENT_ID<span id="n0" data-name="SYNC_STRAVA_CLIENT_ID"></span><span id="v0">#{cid}</span></code></div>
            <div class="box" style="margin-top:0.5rem"><button class="copy" onclick="cn('n1')">📋 Name</button><button class="copy" style="margin-left:0.3rem" onclick="cv('v1')">📋 Value</button>
            <code>Name:  SYNC_STRAVA_CLIENT_SECRET<span id="n1" data-name="SYNC_STRAVA_CLIENT_SECRET"></span><span id="v1">#{csec}</span></code></div>
            <div class="box" style="margin-top:0.5rem"><button class="copy" onclick="cn('n2')">📋 Name</button><button class="copy" style="margin-left:0.3rem" onclick="cv('v2')">📋 Value</button>
            <code>Name:  SYNC_STRAVA_REFRESH_TOKEN<span id="n2" data-name="SYNC_STRAVA_REFRESH_TOKEN"></span><span id="v2">#{rt}</span></code></div>
            <a class="action-btn" href="#{gh_url}" target="_blank">Open GitHub Secrets ↗</a></div>
            <hr>
            <div class="section compact"><h2>💻 本地配置 / Local Config</h2>
            <div class="box" style="border-left:3px solid #2a2"><code>✓ 已自动写入 #{config_path.sub(Dir.home, "~")}
          <span style="color:#888">strava:
            refresh_token: #{rt}</span></code></div></div>
            <hr>
            <p style="text-align:center;color:#666;font-size:0.8rem">复制完成后点击下方按钮关闭服务器<br>Click the button below to close the server</p>
            <div style="text-align:center"><button onclick="fetch('/shutdown').then(function(){document.body.innerHTML='<h1 style=text-align:center;margin-top:40vh>✓ Server closed</h1>'})" style="background:#555;color:#fff;border:none;border-radius:6px;padding:0.6rem 1.5rem;font-size:0.9rem;cursor:pointer">🛑 Close Server</button></div></div>
            <script>function cn(id){navigator.clipboard.writeText(document.getElementById(id).dataset.name).then(function(){var b=event.target;b.textContent='✓';setTimeout(function(){b.textContent='📋 Name'},2000)})}function cv(id){navigator.clipboard.writeText(document.getElementById(id).textContent).then(function(){var b=event.target;b.textContent='✓';setTimeout(function(){b.textContent='📋 Value'},2000)})}</script></body></html>
        HTML
      end
    end
  end
end
