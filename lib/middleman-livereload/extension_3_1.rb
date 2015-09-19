require 'rack/livereload'
require 'middleman-livereload/reactor'

module Middleman
  class LiveReloadExtension < Extension
    option :port, '35729', 'Port to bind the LiveReload API server to'
    option :apply_js_live, true, 'Apply JS changes live, without reloading'
    option :apply_css_live, true, 'Apply CSS changes live, without reloading'
    option :no_swf, false, 'Disable Flash WebSocket polyfill for browsers that support native WebSockets'
    option :host, Socket.ip_address_list.find(->{ Addrinfo.ip 'localhost' }, &:ipv4_private?).ip_address, 'Host to bind LiveReload API server to'
    option :ignore, [], 'Array of patterns for paths that must be ignored'
    option :bundle_css_files, ['stylesheets/application.css'], 'Array of patterns that include bundle files'

    def initialize(app, options_hash={}, &block)
      super

      if app.respond_to?(:server?)
        return unless app.server?
      else
        return unless app.environment == :development
      end

      @reactor = nil

      port = options.port.to_i
      host = options.host
      no_swf = options.no_swf
      ignore = options.ignore
      bundle_files = options.bundle_css_files
      options_hash = options.to_h

      app.ready do
        if @reactor
          @reactor.app = self
        else
          @reactor = ::Middleman::LiveReload::Reactor.new(options_hash, self)
        end

        files.changed do |file|
          next if files.respond_to?(:ignored?) && files.send(:ignored?, file)

          logger.debug "LiveReload: File changed - #{file}"

          reload_path = "#{Dir.pwd}/#{file}"

          file_url = sitemap.file_to_path(file)
          if file_url
            file_resource = sitemap.find_resource_by_path(file_url)
            if file_resource
              reload_path = file_resource.url
            elsif file.basename.to_s[0] == '_'
              reload_path = bundle_files.map do |bundle_path|
                file_resource = sitemap.find_resource_by_path(bundle_path)

                if file_resource
                  path = file_resource.file_descriptor.full_path
                  app.files.watcher_for_path([:source], path).send(:update, [path], [])
                  path.to_s
                else
                  nil
                end
              end.compact

              logger.debug "LiveReload: Reloading bundles - #{reload_path.inspect}"
            end
          end

          @reactor.reload_browser(reload_path)
        end

        files.deleted do |file|
          next if files.respond_to?(:ignored?) && files.send(:ignored?, file)

          logger.debug "LiveReload: File deleted - #{file}"

          @reactor.reload_browser("#{Dir.pwd}/#{file}")
        end

        # Use the vendored livereload.js source rather than trying to get it from Middleman
        # https://github.com/johnbintz/rack-livereload#which-livereload-script-does-it-use
        use ::Rack::LiveReload, port: port, host: host, no_swf: no_swf, source: :vendored, ignore: ignore
      end
    end
  end
end
