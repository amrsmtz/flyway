module OpenMeteo
  class PlanLiveJob < ApplicationJob
    def perform
      Planner.new.plan_live
    end
  end
end
