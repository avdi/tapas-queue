require "tapas/queue/version"
require "thread"

module Tapas
  class Queue
    def initialize(max_size = :infinite)
      @items           = []
      @max_size        = max_size
      @lock            = Mutex.new
      @space_available = ConditionVariable.new
      @item_available  = ConditionVariable.new
    end

    def push(obj, timeout=:never, &timeout_policy)
      timeout_policy ||= -> do
        raise "Push timed out"
      end
      wait_for_condition(
        @space_available,
        ->{!full?},
        timeout,
        timeout_policy) do

        @items.push(obj)
        @item_available.signal
      end
    end

    def pop(timeout = :never, &timeout_policy)
      timeout_policy ||= ->{nil}
      wait_for_condition(
        @item_available,
        ->{@items.any?},
        timeout,
        timeout_policy) do

        item = @items.shift
        @space_available.signal unless full?
        item
      end
    end

    private

    def full?
      return false if @max_size == :infinite
      @max_size <= @items.size
    end

    def wait_for_condition(
        cv, condition_predicate, timeout=:never, timeout_policy=->{nil})
      deadline = timeout == :never ? :never : Time.now + timeout
      @lock.synchronize do
        loop do
          cv_timeout = timeout == :never ? nil : deadline - Time.now
          if !condition_predicate.call && cv_timeout.to_f >= 0
            cv.wait(@lock, cv_timeout)
          end
          if condition_predicate.call
            return yield
          elsif deadline == :never || deadline > Time.now
            next
          else
            return timeout_policy.call
          end
        end
      end
    end
  end
end
