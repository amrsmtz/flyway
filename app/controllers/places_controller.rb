class PlacesController < ApplicationController
  def index
    @query = params[:q].to_s.strip
    @result = Places::Resolver.new.call(@query) if @query.present?
  end
end
