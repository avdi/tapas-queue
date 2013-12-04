require "tapas/queue/version"
require "thread"

module Tapas
  class Condition
    def initialize(lock)
      @lock = lock
      @cv   = ConditionVariable.new
    end

    def wait(timeout=nil)
      @cv.wait(@lock.mutex, timeout)
    end

    def signal
      @cv.signal
    end
  end

  class Lock
    attr_reader :mutex

    def initialize
      @mutex = Mutex.new
    end

    def synchronize(&block)
      @mutex.synchronize(&block)
    end
  end

  class Queue
    class SpaceAvailableCondition
      def initialize(queue, lock, condition)
        @queue     = queue
        @lock      = lock
        @condition = condition
      end

      def signal
        condition.signal
      end

      def wait_for_condition(
          condition_predicate, timeout=:never, timeout_policy=->{nil})
        deadline = timeout == :never ? :never : Time.now + timeout
        @lock.synchronize do
          loop do
            cv_timeout = timeout == :never ? nil : deadline - Time.now
            if !condition_predicate.call && cv_timeout.to_f >= 0
              condition.wait(cv_timeout)
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

      private

      attr_reader :condition
    end

    def initialize(max_size = :infinite, options={})
      @items           = []
      @max_size        = max_size
      @lock            = options.fetch(:lock) { Lock.new }
      @space_available = options.fetch(:space_available_condition) {
        Condition.new(@lock)
      }
      @space_available_condition = SpaceAvailableCondition.new(
        self, @lock, @space_available)
      @item_available  = options.fetch(:item_available_condition) {
        Condition.new(@lock)
      }
    end

    def push(obj, timeout=:never, &timeout_policy)
      timeout_policy ||= -> do
        raise "Push timed out"
      end
      @space_available_condition.wait_for_condition(
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
        @space_available_condition.signal unless full?
        item
      end
    end

    private

    def wait_for_condition(
        cv, condition_predicate, timeout=:never, timeout_policy=->{nil})
      deadline = timeout == :never ? :never : Time.now + timeout
      @lock.synchronize do
        loop do
          cv_timeout = timeout == :never ? nil : deadline - Time.now
          if !condition_predicate.call && cv_timeout.to_f >= 0
            cv.wait(cv_timeout)
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

    def full?
      return false if @max_size == :infinite
      @max_size <= @items.size
    end

  end
end
