# Redis::Lock

Yet another gem for pessimistic locking using Redis. 

The gem uses unique identifiers for the lock values instead of timestamps as described in [the Redis SETNX documentation](http://redis.io/commands/setnx).
This avoids any issues with the clocks on the client and server not being exactly in sync. While this shouldn't occur, it does and the implementation described here could fail if the client is more than 1 second out of sync with the server.

The gem uses a combination of [SETNX](http://redis.io/commands/setnx) and [EXPIRES](http://redis.io/commands/expires) instead of [GETSET](http://redis.io/commands/getset) as described in the lock implementation on the redis site. If a client crashes between issuing the 
SETNX and the EXPIRES commands, the next client that attempts to get a lock will set the EXPIRES on the lock and wait as normal 
( just in case there is a legitimate lock in use and something else happened ).

When attempting to remove the lock, the client verifies that they are still the lock owner before removing it. The gem watches the lock key while
attempting to remove the lock to catch the case where the lock expires and is acquired by another client between checking ownership and deleting the lock.
If the lock is changed while attempting to remove the lock, the removal process will be tried again.


## Installation

Add this line to your application's Gemfile:

    gem 'bfg-redis-lock'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install bfg-redis-lock

## Usage

    require 'redis'
    require 'redis-lock'

Once required, you can do things like:

    redis = Redis.new
    redis.lock "my_key" do |lock|
      # do something while locked
    end
    
The block form above ensures that the lock is released after the block has been executed. Alternatively, you can choose to not provide a block and
work directly with the lock:

    redis = Redis.new
    lock = redis.lock "my_key"

    # do some stuff
    
    lock.unlock

If you would like, you can specify a timeout for acquiring the lock as well as the lock duration in seconds. The defaults are 5 seconds for acquiring a lock and 10 seconds for the lock duration:

    redis = Redis.new
    redis.lock "my_key", :acquire_timeout => 2, :lock_duration => 5 do |lock|
      # do something
    end

If the lock can't be acquired before the timeout, a LockError will be raised:

    redis = Redis.new
    lock = redis.lock "my_key", :lock_duration => 30
    redis.lock "my_key", :acquire_timeout => 1 # raises a LockError after one second of attempting to acquire the lock

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
