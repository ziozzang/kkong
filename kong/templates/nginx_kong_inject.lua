return [[
> if LUA_SSL_VERIFY_DEPTH and tonumber(LUA_SSL_VERIFY_DEPTH) ~= 1 then
lua_ssl_verify_depth   ${{LUA_SSL_VERIFY_DEPTH}};
> end
> if lua_ssl_trusted_certificate_combined then
lua_ssl_trusted_certificate '${{LUA_SSL_TRUSTED_CERTIFICATE_COMBINED}}';
> end
lua_ssl_protocols ${{NGINX_HTTP_LUA_SSL_PROTOCOLS}};
]]
