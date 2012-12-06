require 'spec_helper'
require 'logger'
require 'benchmark'

describe Redis::Lock do
  
  let(:redis) { Redis.new }
  
  before(:each) do
    redis.del "lock:test"
  end

  it "responds to lock" do
    redis.should respond_to(:lock)
  end
  
  it "can acquire and release a lock" do
    lock = redis.lock "test"
  
    redis.get("lock:test").should eq(lock.id)
    lock.should be_locked
    
    lock.unlock
  
    redis.get("lock:test").should be_nil
    lock.should_not be_locked
  end
  
  it "processes a provided block and ensures that the lock is release when completed" do
    lock = redis.lock "test" do |lock|
      redis.set "test", "hello"
      lock.should be_locked
    end
  
    redis.get("test").should eq("hello")
    lock.should_not be_locked
  end
  
  it "prevents other clients from obtaining a lock" do
    lock = redis.lock "test", :lock_duration => 10
    expect { redis.lock "test", :acquire_timeout => 1 }.to raise_exception
    lock.unlock
  end
  
  it "expires the locks appropriately" do
    lock = redis.lock "test", :lock_duration => 1
    sleep(2)
    lock.should_not be_locked
  end
  
  it "handles clients crashing between obtaining a lock and setting the expires" do
    redis.set "lock:test", "xxx"
    
    lock = redis.lock("test", :acquire_timeout => 5, :lock_duration => 1)
    lock.should be_locked
    
    redis.get("lock:test").should_not eq("xxx")
    redis.get("lock:test").should eq(lock.id)
    redis.ttl("lock:test").should_not eq(-1)
    lock.unlock
  end
  
  it "doesn't remove the lock if the lock expires before complete and another client aquires the lock" do
    lock1 = redis.lock "test", :lock_duration => 1
    lock2 = redis.lock "test", :acquire_timeout => 3
    lock1.unlock
    
    lock1.should_not be_locked
    redis.get("lock:test").should eq(lock2.id)
    lock2.should be_locked
  
    lock2.unlock
  end
  
  it "retries removing the lock when another client changes it during delete" do
    callback = Proc.new do |redis|
      redis.incr "retry_count"

      # mess with the lock using another client
      unless redis.get("retry_count").to_i > 1
        Redis.new.expires "lock:test", 60
      end
    end
    
    redis.set "retry_count", 0
    lock = redis.lock "test"
    lock.before_delete_callback = callback
    lock.unlock
    
    redis.get("retry_count").should eq(2.to_s)
    lock.should_not be_locked
  end
  
  it "doesn't remove the lock when another client changes it" do
    callback = Proc.new do |redis|
      redis.incr "retry_count"

      # mess with the lock using another client
      unless redis.get("retry_count").to_i > 1
        Redis.new.set "lock:test", "xxx"
      end
    end
    
    redis.set "retry_count", 0
    lock = redis.lock "test"
    lock.before_delete_callback = callback
    lock.unlock
    
    redis.get("retry_count").should eq(1.to_s)
    lock.should_not be_locked
    redis.get("lock:test").should eq("xxx")
    
    redis.del("lock:test")
  end
  
  it "can extend a lock we own" do
    lock = redis.lock "test", :lock_duration => 10
    lock.extend_lock 30
    
    redis.ttl("lock:test").should eq(30)

    lock.unlock
  end
  
  it "can't extend a lock we don't own" do
    lock1 = redis.lock "test", :lock_duration => 1
    lock2 = redis.lock "test"
    
    expect { lock1.extend_lock 30 }.to raise_exception
    
    lock1.unlock
    lock2.unlock
  end
  
  it "will retry the lock extension if the key changes while we are doing the extension" do
    callback = Proc.new do |redis|
      redis.incr "retry_count"

      # mess with the lock using another client
      unless redis.get("retry_count").to_i > 1
        Redis.new.expires "lock:test", 60
      end
    end
    
    redis.set "retry_count", 0
    lock = redis.lock "test", :lock_duration => 10
    lock.before_extend_callback = callback
    lock.extend_lock 30
    
    redis.get("retry_count").should eq(2.to_s)
    lock.should be_locked

    lock.unlock
  end
  
  it "can run a lot of times without any conflicts" do
    redis.set "num_locks", 0
    threads = []
    logger = Logger.new(STDOUT)
    # logger.level = Logger::INFO
    logger.level = Logger::WARN
    
    time = Benchmark.realtime do
      10.times do 
        threads << Thread.new do
          10.times do
            Redis.new.lock("test", :lock_duration => 1, :logger => logger) do |lock|
              lock.redis.incr "num_locks"
            end
            sleep(0.1)
          end
        end
      end
      threads.each { |t| t.join }
    end
    
    redis.get("num_locks").should eq(100.to_s)
  end
  
end
