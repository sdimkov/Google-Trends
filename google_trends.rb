#!/usr/bin/env ruby


require 'rubygems'
require 'uri'
require 'httpclient'
require 'optparse'


module GoogleTrends

  DEFAULT_USERNAME = nil
  DEFAULT_PASSWORD = nil
  DEFAULT_LOCATION = nil
  DEFAULT_CATEGORY = nil
  DEFAULT_SEARCH   = 'web'
  DEFAULT_OUTPUT   = nil


  def self.console_application
    options = {}
    username, password = nil, nil
    output, results    = nil, ''

    # Setup console interface
    optparse = OptionParser.new do |opts|
      opts.banner = "Usage google_trends.rb [options] keyword1 keyword2 ..."

      options[:geo] = DEFAULT_LOCATION
      opts.on( '-L', '--location AREA', 'Search in specific location') do |area|
        options[:geo] = area
      end

      options[:cat] = DEFAULT_CATEGORY
      opts.on( '-C', '--category CATG', 'Search in specific category' ) do |catg|
        options[:cat] = catg
      end

      options[:gprop] = DEFAULT_SEARCH
      opts.on( '-S', '--search TYPE', ['web', 'news', 'images', 'shopping', 'youtube'], 
          'Specify search type. Default is web',
          'Can be one of the following:',
          'web, news, images, shopping, youtube') do |type|
        options[:gprop] = type.gsub 'shopping', 'froogle'
      end

      opts.on( '-N', '--no-formatting', 'Keep original formatting of the CSV report' ) do
        options[:no_format] = true
      end

      username = DEFAULT_USERNAME
      opts.on( '-U', '--username USER', 'Google account username/email') do |user|
        username = user
      end

      password = DEFAULT_PASSWORD
      opts.on( '-P', '--password PASS', 'Google account password') do |pass|
        password = pass
      end

      output = DEFAULT_OUTPUT
      opts.on( '-O', '--output FILE', 'Save results from all queries in the specified file') do |file|
        output = file
      end

      opts.on( '-H', '--help', 'Display this screen' ) do
       puts opts
       exit
      end
    end

    # Parse command-line arguments
    optparse.parse!

    # Process all search terms
    unless ARGV.empty?
      client = Client.new username, password
      ARGV.each do |query|
        options[:q] = query
        report = client.download_csv_report options
        if output
          results += report.to_s
        else
          report.save "#{query}.csv"
        end
      end
      Report.new(results).save output if output
    else
      puts 'Provide at least one search term'
    end

  end

  class Client

    def initialize username, password
      unless username.is_a? String and password.is_a? String and 
             username.size > 1     and password.size > 1
        raise 'Provide valid username and password for Google authentication'
      end
      puts "\nLogin in Google Trends as #{username} ..."
      
      @login_params = {
        'continue'         => 'http://www.google.com/trends',
        'PersistentCookie' => 'yes',
        'Email'            => username,
        'Passwd'           => password,
      }
      @headers = {
        'Referrer'     => 'https://www.google.com/accounts/ServiceLoginBoxAuth',
        'User-Agent'   => 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/535.21 (KHTML, like Gecko) Chrome/19.0.1042.0 Safari/535.21',
        'Content-type' => 'application/x-www-form-urlencoded',  
        'Accept'       => 'text/plain'
      }
      @url_ServiceLoginBoxAuth = 'https://accounts.google.com/ServiceLoginBoxAuth'
      @url_Export              = 'http://www.google.com/trends/trendsReport'
      @url_CookieCheck         = 'https://www.google.com/accounts/CheckCookie?chtml=LoginDoneHtml'
      @url_PerfCookie          = 'http://www.google.com'
      
      @client = HTTPClient.new()
      uri = URI.parse @url_ServiceLoginBoxAuth
      res = @client.get uri,@headers


      galx = res.body.match /<input name="GALX" type="hidden"\n\s+value="([a-zA-Z0-9_-]+)">/i
      unless galx
        puts 'No GALX found'
        return
      end
      @login_params['GALX'] = galx.captures[0]
      
      @client.post uri, @login_params
      @client.get URI.parse @url_CookieCheck
      @client.get URI.parse @url_PerfCookie
      puts 'Login success.'
    end
    
    def download_csv_report params = {}
      params = {
        'hl'      => 'en',
        'content' => '1',
        'export'  => '1',
        'q'       => nil,  # Query term
        'geo'     => nil,  # Location
        'cat'     => nil,  # Category
        'gprop'   => nil,  # Search type
      }.merge params

      params.keys.each do |key|
        params[key.to_s] = params.delete key unless key.is_a? String
      end
      params.each do |key, value|
        params.delete key if value.nil?
      end
      params.delete 'gprop' if params['gprop'] == 'web'
      no_format = params.delete 'no_format'
      
      puts "\nDownload CSV report for #{params['q']} ..."
      data = @client.get_content @url_Export, params
      unless no_format  # crop irrelevant parts of the report
        data = data.to_s.split("Interest over time\n").last.split("\n\n").first
      end

      puts 'Report download success.'
      return Report.new data
    end
    
  end  # class GoogleTrends::Client


  class Report

    def initialize data
      @data = data
    end

    def to_s
      @data
    end

    def to_csv
    end

    def save filename
      file = File.new filename, 'w'
      file.write @data.to_s
      file.close
    end

  end  # class GoogleTrends::Report


end  # module GoogleTrends


# Run the console app
GoogleTrends.console_application
