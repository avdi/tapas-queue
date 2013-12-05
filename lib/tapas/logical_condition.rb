module Tapas
  class LogicalCondition
    def initialize(
        client:    nil,
        lock:      Lock.new,
        condition: Condition.new(lock),
        test:      ->{false})
      @client    = client
      @lock      = lock
      @condition = condition
      @test      = test
    end

    def signal
      condition.signal
    end

    def wait(timeout=:never, timeout_policy=->{nil})
      deadline = timeout == :never ? :never : Time.now + timeout
      @lock.synchronize do
        loop do
          cv_timeout = timeout == :never ? nil : deadline - Time.now
          if !condition_holds? && cv_timeout.to_f >= 0
            condition.wait(cv_timeout)
          end
          if condition_holds?
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

    def condition_holds?
      test.call
    end

    attr_reader :client, :condition, :test
  end
end
