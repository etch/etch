class FilesController < ApplicationController
  # POST /files
  # The method name doesn't exactly make sense in this case (since database
  # entries are only indirectly created here, there is no File model), but it
  # is consistent with the method name associated with POST in RESTful
  # controllers, and thus also falls into the actions that are checked for
  # authentication by our before_filter.
  def create
    response = nil
    begin
      etchserver = Etch::Server.new(params[:facts], params[:tag], params[:debug])
      response = etchserver.generate(params[:files])
      render :text => response
    rescue Exception => e
      logger.error e.message
      logger.info e.backtrace.join("\n") if params[:debug]
      response = e.message
      response << e.backtrace.join("\n") if params[:debug]
      render :text => response, :status => :internal_server_error
    end
  end
end
