require "spec_helper"
require "tapas/queue"
require "timeout"

module Tapas
  describe Queue do
    specify "simple pushing and popping" do
      q = Queue.new
      q.push "hello"
      q.push "world"
      expect(q.pop).to eq("hello")
      expect(q.pop).to eq("world")
    end

    specify "waiting for an item" do
      q = Queue.new
      consumer = Thread.new do
        q.pop
      end
      wait_for { consumer.status == "sleep" }
      q.push "hello"
      expect(consumer.value).to eq("hello")
    end

    def wait_for
      Timeout.timeout 1 do
        sleep 0.001 until yield
      end
    end
  end
end
