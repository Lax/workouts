require "stravaweblib"
require "http/cookie_jar"
require "tmpdir"
require "base64"
require "json"

def jwt_payload(sub:, exp: nil)
  data = { "sub" => sub }
  data["exp"] = exp if exp
  header = Base64.urlsafe_encode64('{"alg":"HS256"}').delete("=")
  payload = Base64.urlsafe_encode64(JSON.generate(data)).delete("=")
  "#{header}.#{payload}.sig"
end

VALID_JWT = jwt_payload(sub: "12345", exp: Time.now.to_i + 86400)
EXPIRED_JWT = jwt_payload(sub: "12345", exp: Time.now.to_i - 86400)

RSpec.describe StravaWebLib::Client do
  let(:session_double) { double("Faraday session") }

  def stub_session(session = session_double)
    allow_any_instance_of(described_class).to receive(:build_session).and_return(session)
    session
  end

  def stub_me_redirect(session = session_double)
    resp = double("response", status: 302, headers: { "location" => "/12345" })
    allow(session).to receive(:get).with("/me").and_return(resp)
    resp
  end

  describe "VERSION" do
    it { expect(StravaWebLib::VERSION).to eq("0.1.0") }
  end

  describe "ExportResult" do
    it "is a Data immutable" do
      r = StravaWebLib::ExportResult.new(filename: "a.fit", content: "b", format: :fit)
      expect(r.filename).to eq("a.fit")
      expect(r.content).to eq("b")
      expect(r.format).to eq(:fit)
    end
  end

  describe "#initialize — auth" do
    it "with no auth raises AuthError with help message" do
      expect { described_class.new }.to raise_error(StravaWebLib::AuthError, /strava-web-auth/)
    end

    it "with empty jwt raises AuthError" do
      expect { described_class.new(jwt: "") }.to raise_error(StravaWebLib::AuthError, /empty/)
    end

    it "with invalid JWT (not 3 parts) raises AuthError" do
      expect { described_class.new(jwt: "one.two") }.to raise_error(StravaWebLib::AuthError, /3 parts/)
    end

    it "with undecodable JWT payload raises AuthError" do
      header = Base64.urlsafe_encode64("{}").delete("=")
      badjwt = "#{header}.!!bad!!.sig"
      expect { described_class.new(jwt: badjwt) }.to raise_error(StravaWebLib::AuthError, /decode/)
    end

    it "with expired JWT raises AuthError" do
      stub_session
      expect { described_class.new(jwt: EXPIRED_JWT) }.to raise_error(StravaWebLib::AuthError, /expired/)
    end

    it "with JWT missing sub claim raises AuthError" do
      header = Base64.urlsafe_encode64("{}").delete("=")
      payload = Base64.urlsafe_encode64('{"exp":9999999999}').delete("=")
      jwt = "#{header}.#{payload}.sig"
      stub_session
      expect { described_class.new(jwt: jwt) }.to raise_error(StravaWebLib::AuthError, /sub/)
    end

    it "with valid JWT sets cookies and verifies session" do
      s = stub_session
      stub_me_redirect(s)

      client = described_class.new(jwt: VALID_JWT, cookie_path: nil)

      cookies = client.instance_variable_get(:@jar).cookies(URI("https://www.strava.com"))
      expect(cookies.map(&:name)).to contain_exactly("strava_remember_id", "strava_remember_token")
      expect(cookies.find { |c| c.name == "strava_remember_id" }.value).to eq("12345")
      expect(client.authenticated?).to be true
    end

    it "with JWT fails if /me verification returns non-302" do
      s = stub_session
      resp = double("response", status: 200, headers: {})
      allow(s).to receive(:get).with("/me").and_return(resp)

      expect { described_class.new(jwt: VALID_JWT) }.to raise_error(StravaWebLib::AuthError, /verification failed/)
    end
  end

  describe "#initialize — auth_seed" do
    before { stub_session; stub_me_redirect }

    it "decodes Base64-encoded JWT" do
      seed = Base64.strict_encode64(VALID_JWT)
      client = described_class.new(auth_seed: seed, cookie_path: nil)
      expect(client.authenticated?).to be true
    end

    it "raises AuthError for non-Base64, non-JWT seed" do
      expect { described_class.new(auth_seed: "not-base64", cookie_path: nil) }
        .to raise_error(StravaWebLib::AuthError, /3 parts/)
    end

    it "skips empty auth_seed" do
      expect { described_class.new(auth_seed: "") }.to raise_error(StravaWebLib::AuthError, /strava-web-auth/)
    end

    it "prefers jwt over auth_seed when both given" do
      seed = Base64.strict_encode64("bogus")
      client = described_class.new(jwt: VALID_JWT, auth_seed: seed, cookie_path: nil)
      expect(client.authenticated?).to be true
    end
  end

  describe "#initialize — cookie persistence" do
    it "loads cookies from file" do
      jar = HTTP::CookieJar.new
      jar << HTTP::Cookie.new("strava_remember_id", "999", domain: ".strava.com", path: "/", secure: true, max_age: 86400)
      jar << HTTP::Cookie.new("strava_remember_token", "valid_jwt", domain: ".strava.com", path: "/", secure: true, max_age: 86400)

      Dir.mktmpdir do |dir|
        path = File.join(dir, "session.yml")
        jar.save(path, :yaml, session: true)

        s = stub_session
        stub_me_redirect(s)

        client = described_class.new(cookie_path: path)
        expect(client.authenticated?).to be true
      end
    end

    it "handles corrupt cookie file gracefully" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "session.yml")
        File.write(path, "!!not yaml!!")

        s = stub_session
        stub_me_redirect(s)

        expect { described_class.new(jwt: VALID_JWT, cookie_path: path) }.not_to raise_error
        expect(File.exist?(path)).to be true
      end
    end

    it "saves cookies after successful auth" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "session.yml")

        s = stub_session
        stub_me_redirect(s)

        described_class.new(jwt: VALID_JWT, cookie_path: path)
        expect(File.exist?(path)).to be true

        jar2 = HTTP::CookieJar.new
        jar2.load(path, :yaml, session: true)
        expect(jar2.cookies(URI("https://www.strava.com"))).not_to be_empty
      end
    end

    it "persist_cookies! saves to file" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "session.yml")

        s = stub_session
        stub_me_redirect(s)

        client = described_class.new(jwt: VALID_JWT, cookie_path: path)
        FileUtils.rm_f(path)
        client.persist_cookies!
        expect(File.exist?(path)).to be true
      end
    end
  end

  describe "#export" do
    let(:client) do
      s = stub_session
      stub_me_redirect(s)
      described_class.new(jwt: VALID_JWT, cookie_path: nil)
    end

    def stub_export(session_double, path, status: 200, body: "data", cd: 'attachment; filename="activity.fit"')
      resp = double("response", success?: status < 400, status: status, body: body,
                     headers: { "Content-Disposition" => cd })
      allow(session_double).to receive(:get).with(path).and_return(resp)
      resp
    end

    it "defaults to format :original" do
      session = client.send(:build_session)
      stub_export(session, "/activities/123/export_original")
      allow(client).to receive(:build_session).and_return(session)

      result = client.export(123)
      expect(result.format).to eq(:fit)
    end

    it "supports format :tcx" do
      session = client.send(:build_session)
      stub_export(session, "/activities/456/export_tcx", cd: 'attachment; filename="activity.tcx"')
      allow(client).to receive(:build_session).and_return(session)

      result = client.export(456, format: :tcx)
      expect(result.filename).to eq("activity.tcx")
      expect(result.format).to eq(:tcx)
    end

    it "supports format :gpx" do
      session = client.send(:build_session)
      stub_export(session, "/activities/789/export_gpx", cd: 'attachment; filename="track.gpx"')
      allow(client).to receive(:build_session).and_return(session)

      result = client.export(789, format: :gpx)
      expect(result.filename).to eq("track.gpx")
      expect(result.format).to eq(:gpx)
    end

    it "raises ArgumentError for unknown format" do
      expect { client.export(1, format: :csv) }.to raise_error(ArgumentError, /unknown format/)
    end

    it "raises ExportError on HTTP failure" do
      session = client.send(:build_session)
      stub_export(session, "/activities/1/export_original", status: 404)
      allow(client).to receive(:build_session).and_return(session)

      expect { client.export(1) }.to raise_error(StravaWebLib::ExportError, /HTTP 404/)
    end
  end

  describe "private: extract_filename" do
    let(:client) do
      s = stub_session
      stub_me_redirect(s)
      described_class.new(jwt: VALID_JWT, cookie_path: nil)
    end

    it "extracts standard quoted filename" do
      cd = 'attachment; filename="morning_run.fit"'
      resp = double("response", headers: { "Content-Disposition" => cd })
      expect(client.send(:extract_filename, resp, 123, :original)).to eq("morning_run.fit")
    end

    it "extracts RFC 5987 encoded filename" do
      cd = 'attachment; filename*=UTF-8\'\'activity%20name.fit'
      resp = double("response", headers: { "Content-Disposition" => cd })
      expect(client.send(:extract_filename, resp, 123, :original)).to eq("activity name.fit")
    end

    it "extracts bare filename" do
      cd = "attachment; filename=data.fit"
      resp = double("response", headers: { "Content-Disposition" => cd })
      expect(client.send(:extract_filename, resp, 123, :original)).to eq("data.fit")
    end

    it "falls back for missing Content-Disposition" do
      resp = double("response", headers: {})
      expect(client.send(:extract_filename, resp, 123, :original)).to eq("123.dat")
    end

    it "falls back for tcx format with default .tcx extension" do
      resp = double("response", headers: {})
      expect(client.send(:extract_filename, resp, 789, :tcx)).to eq("789.tcx")
    end
  end

  describe "private: infer_format" do
    let(:client) do
      s = stub_session
      stub_me_redirect(s)
      described_class.new(jwt: VALID_JWT, cookie_path: nil)
    end

    it "infers :fit from .fit extension" do
      expect(client.send(:infer_format, "file.fit", :unknown)).to eq(:fit)
    end

    it "infers :tcx from .tcx extension" do
      expect(client.send(:infer_format, "file.tcx", :unknown)).to eq(:tcx)
    end

    it "infers :gpx from .gpx extension" do
      expect(client.send(:infer_format, "file.gpx", :unknown)).to eq(:gpx)
    end

    it "infers :json from .json extension" do
      expect(client.send(:infer_format, "file.json", :unknown)).to eq(:json)
    end

    it "falls back to source_format for unknown extensions" do
      expect(client.send(:infer_format, "file.dat", :original)).to eq(:original)
    end
  end
end
