require "spec_helper"
require "tapas/queue"
require "timeout"

module Tapas
  describe Queue do
    specify "waiting for an item" do
      q = Queue.new
      consumer = Thread.new do
        q.pop
      end
      wait_for { consumer.status == "sleep" }
      q.push "hello"
      expect(consumer.value).to eq("hello")
    end

    class FakeCondition
      def wait(timeout)
        SyncThread.interrupt(self, :wait, timeout)
      end
      def signal
        SyncThread.interrupt(self, :signal)
      end
    end

    class FakeLock
      def synchronize
        yield
      end
    end

    class SyncThread
      def self.interrupt(source, name, *args, &block)
        Fiber.yield(:interrupt, source, name, args, block)
      end

      def initialize
        @status = Started.new
        @fiber = Fiber.new do
          return_value = nil
          loop do
            op = Fiber.yield(:finish, return_value)
            return_value = op.call
          end
        end
        @fiber.resume
      end

      def run(options={}, &op)
        raise "Not finished!" unless @status.finished?
        execute(options) do
          @fiber.resume(op)
        end
        @status
      end

      def resume(options={})
        raise "Nothing to resume!" if @status.finished?
        execute(options) do
          @fiber.resume
        end
        @status
      end

      def finish
        return @status if @status.finished?
        resume(ignore: true)
      end

      private

      def execute(options={})
        ignores = Array(options[:ignore])
        loop do
          status, *rest = yield
          case status
          when :finish
            @status = Finished.new(rest.first)
            break
          when :interrupt
            source, name, args, block = *rest
            @status = Interrupted.new(source, name, args, block)
            break unless ignores.include?(name) || ignores.include?(true)
          else
            raise "Should never get here"
          end
        end
      end

      class Started
        def finished?; true; end
      end
      Finished = Struct.new(:return_value) do
        def finished?; true; end
        def interrupted_by?(*); false; end
      end
      Interrupted = Struct.new(:source, :name, :arguments, :block) do
        def finished?; false; end
        def interrupted_by?(source_or_message, message=nil, args=nil)
          if args
            return false unless args === arguments
          end
          if message
            return false unless message === name
            return source_or_message === source
          end
          return source_or_message === name
        end
      end
    end


    specify "waiting to push" do
      producer = SyncThread.new
      consumer = SyncThread.new
      q = Queue.new(3,
        lock: FakeLock.new,
        space_available_condition: space_available = FakeCondition.new,
        item_available_condition:  item_available = FakeCondition.new)
       producer.run(ignore: [:signal]) do
        3.times do |n|
          q.push "item #{n+1}"
        end
      end
      expect(
        producer.run(ignore: [:signal]) do
          q.push "item 4"
        end
      ).to be_interrupted_by(space_available, :wait)
      expect(
        consumer.run do
          q.pop
        end
      ).to be_interrupted_by(space_available, :signal)
      consumer.finish
      expect(producer.resume(ignore: [:signal])).to be_finished
      status = consumer.run(ignore: [:signal]) do
        3.times.map { q.pop }
      end
      expect(status.return_value).to eq(["item 2", "item 3", "item 4"])
    end

    def wait_for
      Timeout.timeout 1 do
        sleep 0.001 until yield
      end
    end
  end
end
