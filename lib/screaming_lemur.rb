require 'screaming_lemur/version'
require 'faraday'
require 'mechanize'

module ScreamingLemur
  class Monkey
    attr_accessor :conn
    def initialize(url = 'http://local.m.apartmentguide.com')
      @conn = Faraday.new(url: url) do |f|
        # f.response :logger
        f.adapter  Faraday.default_adapter
      end
    end

    def get(url)
      conn.get(url)
    end

  end

  class Automata
    attr_accessor :config, :base_url
    def initialize(config = "config.yml")
      @filename = File.expand_path(config)
      @config = YAML.load_file(@filename)
      run
      exit(set_exit_status)
    end

    def set_exit_status
      @exit_status ||= 0
    end

    def run
      config[:secondary_urls].each do |request|
        @teacher = Teacher.new(url_base: config[:base_url], url_end: request[:url])
        request[:assertions].each do |assert|
          assert.each do |test, expectation|
            unless @teacher.send(test, expectation)
              @exit_status = 9
            end
          end
        end
      end
    end
  end

  class Teacher
    attr_accessor :response, :full_url
    def initialize(url_base: :error_missing_url_base, url_end: :error_missing_end_url)
      @monk = Monkey.new(url_base)
      @response = @monk.get("#{url_end}")
      @full_url = url_base + url_end
    end

    def status(expected_status = 200)
      func = ->() { response.status == expected_status.to_i }
      make_assertion(func.call, __method__, [response.status, expected_status.to_i])
    end

    def canonical_link(link)
      func = ->(){ gather_canonical_link == link }
      make_assertion(func.call, __method__, [gather_canonical_link, link])
    end

    def make_assertion(function, name, expectations)
      if function
        true
      else
        STDOUT.puts "Failed assertion: #{full_url} : #{name} : Expectation: #{expectations}"
        false
      end
    end

    def gather_canonical_link
      if @response.body[/canonical' href='/]
        @response.body.match(%r{canonical' href='(.+)'})[1]
      else
        ""
      end
    end
  end
end
