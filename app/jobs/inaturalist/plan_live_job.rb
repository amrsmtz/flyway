module Inaturalist
  class PlanLiveJob < ApplicationJob
    def perform
      Planner.new.plan_live
    end
  end
end
