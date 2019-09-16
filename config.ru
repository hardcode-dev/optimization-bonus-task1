# falcon serve -c config.ru

# Middleware that responds to incoming requests:
require 'sinatra/base'
require 'async'
class MyApp < Sinatra::Base
  OVERHEAT_LIMITS = { a: 3, b: 2, c: 1 }.freeze
  WORK_TIMES = { a: 1, b: 2, c: 1 }.freeze
  WORK = {
    a: ->(value) { Digest::MD5.hexdigest(value) },
    b: ->(value) { Digest::SHA256.hexdigest(value) },
    c: ->(value) { Digest::SHA512.hexdigest(value) },
  }
  OVERHEAT_PENALTY = 10 # seconds

  def initialize(args)
    super
    setup
  end

  # GET /a?value=1
  get "/a" do
    process(:a, params)
  end

  get "/b" do
    process(:b, params)
  end

  get "/c" do
    process(:c, params)
  end

  private

  def setup
    @@count = { a: 0, b: 0, c: 0 }
    @@mutex = Mutex.new
  end

  def process(type, params)
    increment_count(type)

    result = Async do |task|
      protect_from_overheat(type: type, task: task)
      log "#{type.to_s.upcase} starts to work"
      task.sleep WORK_TIMES[type]
      result = WORK[type].call(params['value'].to_s)
      log "#{type.to_s.upcase} is done working with #{result}"
      result
    end.wait

    decrement_count(type)
    [200, {}, [result]]
  end

  def increment_count(type)
    @@mutex.synchronize do
      @@count[type] += 1
    end
  end

  def decrement_count(type)
    @@mutex.synchronize do
      @@count[type] -= 1
    end
  end

  def protect_from_overheat(type:, task:)
    if @@count[type] > OVERHEAT_LIMITS[type]
      log "Counters: #{@@count}"
      log "OVERHEAT IN #{type}!!!"
      log "SLEEP FOR #{OVERHEAT_PENALTY} SECONDS TO COOL DOWN!"
      task.sleep OVERHEAT_PENALTY
      log "Counters: #{@@count}"
    end
  end

  def log(msg)
    puts msg
  end
end

# Build the middleware stack:
use MyApp # Then, it will get to Sinatra.
run lambda {|env| [404, {}, []]} # Bottom of the stack, give 404.
