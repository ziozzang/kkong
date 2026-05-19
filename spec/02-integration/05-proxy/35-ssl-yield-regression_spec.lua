local ssl_fixtures = require "spec.fixtures.ssl"
local helpers = require "spec.helpers"
local fmt = string.format


local function get_cert(server_name)
  local _, _, stdout = assert(helpers.execute(
    fmt("echo 'GET /' | openssl s_client -connect 0.0.0.0:%d -servername %s",
        helpers.get_proxy_port(true), server_name)
  ))

  return stdout
end


for _, strategy in helpers.all_strategies({ "postgres", "off" }) do
  describe("SSL certificate yield regression [#" .. strategy .. "]", function()
    local proxy_ssl_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, {
        "routes",
        "services",
        "certificates",
        "snis",
      })

      local exact_service = bp.services:insert {
        name = "exact-sni-service",
        url = helpers.mock_upstream_url,
      }

      bp.routes:insert {
        protocols = { "https" },
        hosts = { "exact.example.test" },
        service = exact_service,
      }

      local wildcard_service = bp.services:insert {
        name = "wildcard-sni-service",
        url = helpers.mock_upstream_url,
      }

      bp.routes:insert {
        protocols = { "https" },
        hosts = { "edge.tls.example.test" },
        service = wildcard_service,
      }

      local exact_cert = bp.certificates:insert {
        cert = ssl_fixtures.cert,
        key = ssl_fixtures.key,
      }

      bp.snis:insert {
        name = "exact.example.test",
        certificate = exact_cert,
      }

      local wildcard_cert = bp.certificates:insert {
        cert = ssl_fixtures.cert_alt,
        key = ssl_fixtures.key_alt,
      }

      bp.snis:insert {
        name = "*.tls.example.test",
        certificate = wildcard_cert,
      }

      assert(helpers.start_kong({
        database = strategy,
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
        pg_host = strategy == "off" and "unknownhost.konghq.com" or nil,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    after_each(function()
      if proxy_ssl_client then
        proxy_ssl_client:close()
        proxy_ssl_client = nil
      end
    end)

    local function assert_tls_route(sni, expected_cn)
      local cert = get_cert(sni)
      assert.is_nil(cert:match("unexpected eof while reading"))
      assert.certificate(cert).has.cn(expected_cn)

      proxy_ssl_client = helpers.proxy_ssl_client(nil, sni)

      local res = assert(proxy_ssl_client:send {
        method = "GET",
        path = "/request",
        headers = {
          Host = sni,
        },
      })

      assert.res_status(200, res)
      assert.equal("mock_upstream", res.headers["X-Powered-By"])
    end

    it("serves the configured exact-match certificate and routes over TLS", function()
      assert_tls_route("exact.example.test", "ssl-example.com")
    end)

    it("serves the configured wildcard certificate and routes over TLS", function()
      assert_tls_route("edge.tls.example.test", "ssl-alt.com")
    end)
  end)
end
