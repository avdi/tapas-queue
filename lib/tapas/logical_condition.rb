module Tapas
  class LogicalCondition
    def initialize(client, lock, condition)
      @client     = client
      @lock      = lock
      @condition = condition
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

    attr_reader :client, :condition
  end
end
