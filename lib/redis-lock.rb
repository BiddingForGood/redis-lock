require "redis"
require "redis-lock/version"
require "securerandom"

class Redis
  
  class Lock
    
    class LockError < StandardError
    end
    
    attr_reader :redis
    attr_reader :id
    attr_reader :lockname
    attr_reader :acquire_timeout
    attr_reader :lock_duration
    attr_reader :logger
    attr_accessor :before_delete_callback
    
    def initialize(redis, lock_name, options = {})
      @redis = redis
      @lockname = "lock:#{lock_name}"
      @acquire_timeout = options[:acquire_timeout] || 5
      @lock_duration = options[:lock_duration] || 10
      @logger = options[:logger]
      
      # generate a unique UUID for this lock
      @id = SecureRandom.uuid
    end
    
    def lock(&block)
      acquire_lock or raise LockError.new(lockname)
      
      if block
        begin
          block.call(self)
        ensure
          release_lock
        end
      end
      
      self
    end
    
    def unlock
      release_lock
      self
    end
    
    def acquire_lock
      try_until = Time.now + acquire_timeout
      
      # loop until now + timeout trying to get the lock
      while Time.now < try_until
        log :debug, "attempting to acquire lock #{lockname}"

        # try and obtain the lock
        if redis.setnx(lockname, id)
          log :info, "lock #{lockname} acquired for #{id}"
          # lock was obtained, so add an expiration
          add_expiration
          return true
        elsif missing_expiration?
          # if no expiration, client that obtained lock likely crashed - add an expiration
          # and wait
          log :debug, "expiration missing on lock #{lockname}"
          add_expiration
        end
        
        # didn't get the lock, sleep briefly and try again
        sleep(0.001)
      end
      
      # was never able to get the lock - give up
      return false
    end
    
    def release_lock
      # we are going to watch the lock key while attempting to remove it, so we can
      # retry removing the lock if the lock is changed while we are removing it.
      release_with_watch do

        log :debug, "releasing #{lockname}..."

        # make sure we still own the lock
        if lock_owner?
          log :debug, "we are the lock owner"
          if before_delete_callback
            log :debug, "calling callback"
            before_delete_callback.call(redis)
          end

          redis.multi do |multi|
            multi.del lockname
          end
          return true
        end
        
        # we weren't the owner of the lock anymore - just return
        return false

      end
    end
    
    def locked?
      lock_owner?
    end
    
    def missing_expiration?
      redis.ttl(lockname) == -1
    end
    
    def add_expiration()
      log :debug, "adding expiration of #{lock_duration} seconds to #{lockname}"
      redis.expire(lockname, lock_duration)
    end
    
    def lock_owner?
      redis.get(lockname) == id
    end
    
    def release_with_watch(&block)
      with_watch do
        begin
          block.call
        rescue => e
          log :warn, "#{lockname} changed while attempting to release key - retrying"
          release_with_watch &block
        end
      end
    end
    
    def with_watch(&block)
      redis.watch lockname
      begin
        block.call
      ensure
        redis.unwatch
      end
    end
    
    def log(level, message)
      if logger
        logger.send(level) { message }
      end
    end
    
  end # Lock class

  def lock(key, options = {}, &block)
    Lock.new(self, key, options).lock(&block)
  end

end
