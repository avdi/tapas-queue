require "spec_helper"
require "tapas/queue"
require "timeout"
require "sync_thread"

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
