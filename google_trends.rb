#!/usr/bin/env ruby


require 'rubygems'
require 'uri'
require 'httpclient'
require 'optparse'
require 'csv'


module GoogleTrends

  DEFAULT_USERNAME = nil
  DEFAULT_PASSWORD = nil
  DEFAULT_LOCATION = nil
  DEFAULT_CATEGORY = nil
  DEFAULT_SEARCH   = 'web'
  DEFAULT_OUTPUT   = nil
  DEFAULT_BREAK    = 0
  DEFAULT_USE_PROXIES     = false
  DEFAULT_CHANGE_ACCOUNTS = false
  DEFAULT_CONNECTION_LIMIT = 800

  PROXIES = [
    "http://186.95.32.209:8080",
    "http://107.170.93.27:3128",
    "http://190.73.142.144:8080",
    "http://190.78.26.232:8080",
    "http://186.88.214.185:8080",
    "http://200.8.139.47:8080"
  ]

  ACCOUNTS = [
    [ 'username@gmail.com', 'password' ],
    [ 'username@gmail.com', 'password' ],
    [ 'username@gmail.com', 'password' ],
    [ 'username@gmail.com', 'password' ],
    [ 'username@gmail.com', 'password' ],
    [ 'username@gmail.com', 'password' ],
    [ 'username@gmail.com', 'password' ],
  ]


  def self.console_application
    
    # Define variables and apply defaults
    options            = {}
    username, password = DEFAULT_USERNAME, DEFAULT_PASSWORD
    output,   input    = DEFAULT_OUTPUT, nil
    pause,    count    = DEFAULT_BREAK, 0
    use_proxies        = DEFAULT_USE_PROXIES
    change_accounts    = DEFAULT_CHANGE_ACCOUNTS
    connection_limit   = DEFAULT_CONNECTION_LIMIT
    used_ips           = [ nil ]

    options[:geo]   = DEFAULT_LOCATION
    options[:cat]   = DEFAULT_CATEGORY
    options[:gprop] = DEFAULT_SEARCH

    # Setup console interface
    optparse = OptionParser.new do |opts|
      opts.banner = "Usage google_trends.rb [options] keyword1 keyword2 ..."
  
      opts.on( '-L', '--location AREA', 'Search in specific location') do |area|
        options[:geo] = area
      end

      opts.on( '-C', '--category CATG', 'Search in specific category' ) do |catg|
        options[:cat] = catg
      end

      opts.on( '-S', '--search TYPE', ['web', 'news', 'images', 'shopping', 'youtube'], 
          'Specify search type. Default is web',
          'Can be one of the following:',
          'web, news, images, shopping, youtube') do |type|
        options[:gprop] = type.gsub 'shopping', 'froogle'
      end

      opts.on( '-N', '--no-formatting', 'Keep original formatting of the CSV report' ) do
        options[:no_format] = true
      end

      opts.on( '-U', '--username USER', 'Google account username/email') do |user|
        username = user
      end

      opts.on( '-P', '--password PASS', 'Google account password') do |pass|
        password = pass
      end

      opts.on( '-I', '--input FILE', 'Read all input queries from the specified file') do |file|
        input = file
      end

      opts.on( '-O', '--output FILE', 'Save results from all queries in the specified file') do |file|
        output = file
      end
      
      opts.on( '-B', '--break N', 'Pause execution of input queries after every N queries processed') do |n|
        pause = n.to_i
      end

      opts.on( '--use-proxies', 'Route the connection via proxies. Uses new proxy',
                                'each time connection limit is reached') do
        use_proxies = true
      end

      opts.on( '-A', '--change-accounts', 'Change user accounts each time connection limit is reached') do
        change_accounts = true
        if not username or not password
          username, password = ACCOUNTS.pop
        end
      end

      opts.on( '--connection-limit N', 'Change the connection after every N queries processed. Must be applied',
                                       'in combination with --use-proxies or --change-accounts to have effect') do |n|
        connection_limit = n.to_i
      end

      opts.on( '-H', '--help', 'Display this screen' ) do
        puts opts
        exit
      end
    end

    # Parse command-line arguments
    optparse.parse!

    # Gather all queries
    queries = []
    ARGV.each do |term|  # queries from command-line
      queries << options.clone
      queries.last[:q] = term
    end
    if input  # queries from input file
      csv_queries = CSV.read input
      csv_queries.shift
      csv_queries.each do |query|
        if query.size > 3
          queries << options.clone
          query[1] = nil if query[1] == 'worldwide'
          query[2] = query[2].downcase.delete(' ').sub('search','')
          query[3] = nil if query[3] == 'all categories'
          queries.last[:q]     = query[0]
          queries.last[:geo]   = query[1]
          queries.last[:gprop] = query[2]
          queries.last[:cat]   = query[3]
        else
          puts 'Invalid input CSV file'
          exit
        end
      end
    end

    # Process all queries
    unless queries.empty?
      client = Client.new username, password
      queries.each do |query|
        if (use_proxies or change_accounts) and client.queries_count > connection_limit
          puts "\nConnection limit reached!"
          if change_accounts
            if ACCOUNTS.empty?
              puts 'No more accounts!'
              exit
            end
            username, password = ACCOUNTS.pop
            puts "Username changed to: " + username
          end
          new_client, new_proxy, ip = nil, nil, nil
          if use_proxies
            while used_ips.include? ip
              if PROXIES.empty?
                puts 'No more proxies!'
                exit
              end
              new_proxy  = PROXIES.pop
              new_client = HTTPClient.new new_proxy
              ip = get_ip new_client
            end
            puts "Proxy changed to: " + new_proxy
          end
          client = Client.new username, password, new_client
        end
        report = client.download_csv_report query
        count += 1
        if pause > 0 and count >= pause
          puts "\n#{count} queries processed.\nPress [ENTER] to continue..."
          $stdin.gets
          count = 0
        end
        if report
          if output
            report.append output
          else
            report.save "#{query['q']}.csv"
          end
        end
      end
    else
      puts 'Provide at least one search query'
      exit
    end

  end

  def self.get_ip client
    url = URI.parse 'http://wtfismyip.com'
    headers = { 
        'Referrer'     => 'https://www.google.com/accounts/ServiceLoginBoxAuth',
        'User-Agent'   => 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/535.21 (KHTML, like Gecko) Chrome/19.0.1042.0 Safari/535.21',
        'Content-type' => 'application/x-www-form-urlencoded',  
        'Accept'       => 'text/html'
    }
    begin
        return client.get(url, headers).body[/\d+\.\d+\.\d+\.\d+/] 
    rescue Exception => e
        return nil
    end
  end


  class Client

    attr_reader :queries_count

    def initialize username, password, http_client = nil
      unless username.is_a? String and password.is_a? String and 
             username.size > 1     and password.size > 1
        raise 'Provide valid username and password for Google authentication'
      end

      @queries_count = 0
      
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
      
      puts "\nLogin in Google Trends as #{username} ..."
      @client = http_client || HTTPClient.new 
      @client.receive_timeout = 10000
      uri = URI.parse @url_ServiceLoginBoxAuth
      res = @client.get uri, @headers

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
      default_params = {
        'hl'      => 'en',
        'content' => '1',
        'export'  => '1',
        'q'       => nil,  # Query term
        'geo'     => nil,  # Location
        'cat'     => nil,  # Category
        'gprop'   => nil,  # Search type
      }

      @queries_count += 1

      params.keys.each do |key|
        params[key.to_s] = params.delete key unless key.is_a? String
      end
      params = default_params.merge params
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

      if data.include? '<div '
        puts 'Report download failed:'
        errors = data.scan />([^<>\n]+)</
        errors.each { |err| puts "  #{err.first}" }
        return nil
      else
        puts 'Report download success.'
        return Report.new data 
      end
     
    end
    
  end  # class GoogleTrends::Client


  class Report

    def initialize data
      @data = data
    end

    def to_s
      @data.to_s
    end

    def to_csv
    end

    def save filename
      file = File.new filename, 'w'
      file.write @data.to_s
      file.close
    end
    
    def append filename
      file = File.new filename, 'a'
      file.write @data.to_s
      file.close
    end

  end  # class GoogleTrends::Report


end  # module GoogleTrends


# Run the console app
GoogleTrends.console_application
