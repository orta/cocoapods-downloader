module Pod
  module Downloader

    # The base class defines the common behaviour of the downloaders.
    #
    # @abstract Subclass and implement {#download}.
    #
    # @private
    #
    class Base

      extend APIExposable
      expose_api API

      # @return [Pathname] the destination folder for the download.
      #
      attr_reader :target_path

      # @return [String] the url of the remote source.
      #
      attr_reader :url

      # @return [Hash={Symbol=>String}] options specific to each concrete
      #         downloader.
      #
      attr_reader :options

      # @param [String, Pathname] target_path @see target_path
      # @param [String] url @see url
      # @param [Hash={Symbol=>String}] options @see options
      #
      def initialize(target_path, url, options)
        require 'pathname'
        @target_path, @url, @options = Pathname.new(target_path), url, options
        @target_path.mkpath
        @max_cache_size = DEFAULT_MAX_CACHE_SIZE
      end

      # @return [String] the name of the downloader.
      #
      # @example Downloader::Mercurial name
      #
      #   "Mercurial"
      #
      def name
        self.class.name.split('::').last
      end

      #-------------------------------------------------------------------------#

      # @!group Configuration

      # @return [Fixnum] The maximum allowed size for the cache expressed in Mb. Defaults to
      #         500Mb.
      #
      # @note   This is specific per downloader class.
      #
      attr_accessor :max_cache_size

      # @return [String] The directory to use as root of the cache. If no
      #         specified the caching will not be used.
      #
      attr_accessor :cache_root

      #-----------------------------------------------------------------------#

      # @!group Downloading

      # Downloads the revision specified in the option of a source. If no
      # revision is specified it fall-back to {#download_head}.
      #
      # @return [void]
      #
      def download
        download_action("#{name} download") do
          download!
          prune_cache
        end
      end

      # Downloads the head revision of a source.
      #
      # @todo Spec for raise.
      #
      # @return [void]
      #
      def download_head
        download_action("#{name} HEAD download") do
          if self.respond_to?(:download_head!, true)
            download_head!
          else
            raise DownloaderError, "The `#{name}` downloader does not support " \
            "the HEAD option."
          end
        end
      end

      # @return [Hash{Symbol=>String}] the options that would allow to
      #         re-download the checked out revision.
      #
      def checkout_options
        raise "Abstract method"
      end

      #-------------------------------------------------------------------------#

      # @!group Cache

      public

      # @return [Pathname] The directory where the cache for the current url
      #         should be stored.
      #
      # @note   The name of the directory is the SHA1 hash value of the URL.
      #
      def cache_path
        require 'digest/sha1'
        if cache_root
          @cache_path ||= class_cache_dir + name + "#{Digest::SHA1.hexdigest(url.to_s)}"
        end
      end

      private

      # @return [Pathname] The directory where the caches are stored.
      #
      def class_cache_dir
        Pathname.new(File.expand_path(cache_root)) + name
      end

      # @return [Bool] Whether the downloader should use the cache.
      #
      def use_cache?
         !cache_root.nil? && !@options[:download_only]
      end

      # The default maximum allowed size for the cache expressed in Mb.
      #
      DEFAULT_MAX_CACHE_SIZE = 500

      # @return [Integer] The global size of the cache expressed in Mb.
      #
      def caches_size
        `du -cm`.split("\n").last.to_i
      end

      # @return [void] Deletes the oldest caches until they the global size is
      #         below the maximum allowed.
      #
      # @todo   Use a hook for the output?
      #
      def prune_cache
        return unless cache_root && class_cache_dir.exist?
        Dir.chdir(class_cache_dir) do
          repos = Pathname.new(class_cache_dir).children.select { |c| c.directory? }.sort_by(&:ctime)
          while caches_size >= max_cache_size && !repos.empty?
            dir = repos.shift
            # UI.message "#{'->'.yellow} Removing #{name} cache for `#{cache_origin_url(dir)}'"
            dir.rmtree
          end
        end
      end

      private

      # Defines two methods for an executable, based on its name. The bag version
      # raises if the executable terminates with a non-zero exit code.
      #
      # For example
      #
      #     executable :git
      #
      # generates
      #
      #     def git(command)
      #       Hooks.execute_with_check("git", command, false)
      #     end
      #
      #     def git!(command)
      #       Hooks.execute_with_check("git", command, true)
      #     end
      #
      # @param  [Symbol] name
      #         the name of the executable.
      #
      # @return [void]
      #
      def self.executable(name)
        define_method(name) do |command|
          execute_command(name.to_s, command, false)
        end

        define_method(name.to_s + "!") do |command|
          execute_command(name.to_s, command, true)
        end
      end
    end
  end
end