class HomeController < ApplicationController
  def index
    connection = ActiveRecord::Base.connection
    @postgres_version = connection.select_value("SHOW server_version")
    @timescaledb_version = connection.select_value("SELECT extversion FROM pg_extension WHERE extname = 'timescaledb'")
  end
end
