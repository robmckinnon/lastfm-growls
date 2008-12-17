require 'rubygems'
require 'open-uri'
require 'json'
require 'uri'
require 'hpricot'

class OsVersion
  attr_reader :ruby_platform, :os, :ident, :version, :build
  def initialize
    @ruby_platform = RUBY_PLATFORM
    if File.exists?("/proc/version")
      @os = :linux
      @ident = File.open("/proc/version").readlines.join
    elsif `sw_vers`.length != 0
      @os = :macosx
      @version = `sw_vers -productVersion`.chop!
      @build = `sw_vers -buildVersion`
    elsif @ruby_platform =~ /(win|w)32$/
      @os = :windows
    end
  end
end

class EventGrowl

  def initialize user, city, loop=true
    @system = OsVersion.new
    @user = user
    @city = city
    puts "User: #{@user}"
    puts "City: #{@city}"
    @base = 'http://ws.audioscrobbler.com/2.0/'
    @logo = File.dirname(__FILE__) + '/last.jpg'
    @last_artist = nil
    @country = Hpricot(open("http://www.last.fm/user/#{@user}")).at('.country-name/text()').to_s
    @messages = {}
    puts 'Country: ' + @country

    while(loop)
      check_now_playing
      sleep(20)
    end
  end

  def check_now_playing
    artist = now_playing

    if new_artist? artist
      check_events(artist)
    elsif artist.nil?
      puts 'no track playing'
    end
  end

  def new_artist? artist
    artist && artist != @last_artist
  end

  def now_playing
    data = lfm("user.getrecenttracks&user=#{@user}")
    tracks = data['recenttracks']['track']
    if tracks.size > 0 && tracks.first['nowplaying'] == 'true'
      tracks.first['artist']['#text']
    else
      nil
    end
  end

  def check_events artist
    @last_artist = artist
    post_events artist
  end

  def post_events artist
    artist_name = URI.escape(artist.tr(' ','+')).sub('&','%26')
    data = lfm("artist.getevents&artist=#{artist_name}")

    if data
      events = data['events']
      if events
        total = events['total']
        if total == '0'
          puts "#{artist} - no events"
        elsif total == '1'
          puts "#{artist} - 1 event"
          event = events['event']
          post_event artist, event
        else
          puts "#{artist} - #{total} events"
          events = events['event']
          events.each { |event| post_event artist, event }
        end
      else
        puts data
      end
    end
  end

  def post_event artist, event
    begin
      name = event['title']
      date = event['startDate']
      location = event['venue']['location']
      country = location['country']
      city = location['city']
      puts "- #{city}, #{country}"
      venue = event['venue']['name']

      if country == @country && city == @city
        info = [name, date, venue, city, country]
        growl(artist, info.join(', ').sub(', ,',',') )
      end
    rescue Exception => e
      puts e.message + ': ' + event.inspect
    end
  end

  private
    def growl title, message
      if @system.os == :macosx
        unless @messages.has_key?(title)
          cmd = "growlnotify -w --sticky -n event_growl --image #{@logo} -p 0 -m \"#{message}\" #{title} &"
          system(cmd)
          @messages[title] = message
        end
      elsif @system.os == :linux
        puts 'not supported'
      elsif @system.os == :windows
        puts 'not supported'
      end
    end

    def lfm method
      url = "#{@base}?method=#{method}&api_key=b59f073118b562ee008b2fb34716f819&format=json"
      result = nil
      json = nil
      begin
        json = open(url).read
        result = JSON.parse( json )
      rescue Exception => e
        puts e.message + ': ' + json.to_s
      end

      result
    end
end

if ARGV.size == 2
  user = ARGV[0]
  city = ARGV[1]
  last_event = EventGrowl.new(user, city)
else
  puts ''
  puts 'usage: ruby lastfm_growls.rb your_user_name your_city'
  puts ''
  puts 'e.g.:  ruby lastfm_growls.rb queen_liz London'
  puts ''
end
