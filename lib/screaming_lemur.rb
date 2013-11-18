require 'screaming_lemur/version'
require 'faraday'
require 'mechanize'
require 'json'
require 'watir-webdriver'
require 'headless'
require 'open-uri'
require 'nokogiri'
require 'headless'
require 'highline/import'


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
    end

    def set_exit_status
      @exit_status ||= 0
    end

    def run
      if config.is_a? Array
        run_multiple_bases
      else
        run_single_base(config)
      end
    end

    def run_multiple_bases
      config.each do |current_config|
        run_single_base(current_config)
      end
    end

    # def self.execute_single(current_config)
    #   a = new(current_config)
    #   a.run_single_base(@config)
    #   exit(a.set_exit_status)
    # end

    def run_single_base(current_config)
      current_config[:secondary_urls].each do |request|
        @teacher = Teacher.new(url_base: current_config[:base_url], url_end: request[:url])
        request[:assertions].each do |assert|
          assert.each do |test, expectation|
            unless @teacher.send(test, expectation)
              @exit_status = 42
            end
          end
        end
      end
    end

    def self.stampede(config)
      a = new(config)
      a.run
      exit(a.set_exit_status)
    end
  end

  class Teacher
    attr_accessor :response, :full_url, :url_base, :url_end
    def initialize(url_base: :error_missing_url_base, url_end: :error_missing_end_url)
      @url_end = url_end
      @url_base = url_base
      @full_url = url_base + url_end
    end


    # assertions
    def status(expected_status = 200)
      mechanize do
        func = ->() { response.status == expected_status.to_i }
        make_assertion(func.call, __method__, [response.status, expected_status.to_i])
      end
    end

    def canonical_link(link)
      mechanize do
        func = ->(){ gather_canonical_link == link }
        make_assertion(func.call, __method__, [gather_canonical_link, link])
      end
    end

    def ops_page_geo_url(expected)
      mechanize do
        actual = gather_ops_page_geo_url
        func = ->(){ actual == expected }
        make_assertion(func.call, __method__, [actual, expected])
      end
    end

    def assert_link(hash)
      assert_link_selector(text: hash[:text])
    end

    def meta_robots(meta)
      mechanize do
        meta_robots_tag = gather_meta_follow_index_tag.split(',').map(&:strip)
        response = meta_robots_tag.include?(meta[0]) && meta_robots_tag.include?(meta[1])
        make_assertion(response, __method__, [gather_meta_follow_index_tag, meta])
      end
    end

    def peel_ad_id(id)
      image_by_id(id, __method__)
    end

    def image_by_id(id, calling_method)
      watir do
        id.gsub!(/\A#/, '')
        response = @browser.img(id: id).exists?
        method = calling_method || __method__
        make_assertion(response, method, [response, true])
      end
    end

    def call_phone_number(css_class)
      watir do
        css_class.gsub!(/\A\./, '')
        response = @browser.span(:class => css_class).exists?
        make_assertion(response, __method__, [response, true])
      end
    end

    def call_phone_number_count(css_class: '', count: 1)
      watir do
        actual_count = Nokogiri::HTML.parse(@browser.body.html).css(css_class).count
        response = (actual_count >= count)
        make_assertion(response, __method__, [actual_count, count])
      end
    end

    def hd_tour_button(css_class)
      watir do
        css_class.gsub!(/\A\./, '')
        response = @browser.link(:class => css_class).exists?
        make_assertion(response, __method__, [response, true])
      end
    end

    def lead_form(css_class)
      watir do
        css_class.gsub!(/\A#/, '')
        response = @browser.form(id: css_class).exists?
        make_assertion(response, __method__, [response, true])
      end
    end

    def lead_form(css_class)
      watir do
        css_class.gsub!(/\A\./, '')
        response = @browser.span(id: css_class).exists?
        make_assertion(response, __method__, [response, true])
      end
    end

    def assert_link_selector(text: 'Check Availability')
      watir do
        response = @browser.link(:text => text).exists?
        make_assertion(response, __method__, [response, true])
      end
    end

    def mechanize(&block)
      @monk = Monkey.new(url_base)
      @response = @monk.get("#{url_end}")
      yield
    end

    def watir(&block)
      headless = Headless.new
      headless.start
      # @browser = Watir::Browser.new
      @browser = Watir::Browser.new :phantomjs
      @browser.goto @full_url
      yield
    ensure
      @browser.close
      headless.destroy
    end

    # support methods
    def make_assertion(function, name, expectations)
      if function
        say "<%= color('Successful url', GREEN) %>: #{full_url} : Assertion: #{name} : Expected: #{expectations[1].inspect}, Actual: #{expectations[0].inspect}"
        true
      else
        say "<%= color('Failed url', RED) %>: #{full_url} : Assertion: #{name} : Expected: #{expectations[1].inspect}, Actual: #{expectations[0].inspect}"
        false
      end
    end

    def gather_meta_follow_index_tag
      nokogiri = Nokogiri::HTML.parse(@response.body)
      node = nokogiri.css('meta[name="ROBOTS"]')
      if node.empty?
        ""
      else
        node.attr('content').value
      end
    end

    def gather_canonical_link
      nokogiri = Nokogiri::HTML.parse(@response.body)
      canonical_node = nokogiri.css('link[rel="canonical"]')
      if canonical_node == []
        ""
      else
        canonical_node.first.attributes["href"].value
      end
    end

    def gather_ops_page_geo_url
      JSON.parse(@response.body)['headers']['HTTP_X_GEO_DATA']
    end
  end
end
