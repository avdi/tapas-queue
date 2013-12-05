require "tapas/queue/version"
require "tapas/logical_condition"
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
    def initialize(max_size = :infinite, options={})
      @items           = []
      @max_size        = max_size
      @lock            = options.fetch(:lock) { Lock.new }
      @space_available_condition = LogicalCondition.new(
        lock: @lock,
        condition: options.fetch(:space_available_condition) {
          Condition.new(@lock)
        },
        test: ->{ !full? })
      @item_available_condition = LogicalCondition.new(
        lock: @lock,
        condition: options.fetch(:item_available_condition) {
          Condition.new(@lock)
        },
        test: ->{ !empty? })
    end

    def push(obj, timeout=:never, &timeout_policy)
      timeout_policy ||= -> do
        raise "Push timed out"
      end
      @space_available_condition.wait(timeout, timeout_policy) do
        @items.push(obj)
        @item_available_condition.signal
      end
    end

    def pop(timeout = :never, &timeout_policy)
      timeout_policy ||= ->{nil}
      @item_available_condition.wait(timeout, timeout_policy) do
        item = @items.shift
        @space_available_condition.signal unless full?
        item
      end
    end

    def full?
      return false if @max_size == :infinite
      @max_size <= @items.size
    end

    def empty?
      @items.empty?
    end
  end
end
