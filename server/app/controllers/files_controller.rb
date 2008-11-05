require 'etchserver'

class FilesController < ApplicationController
  # Turn off this Rails security mechanism, as it is doesn't work in the
  # way this application works.  It expects POST requests to include a
  # token that it auto-inserts into forms, but our POST requests aren't
  # form data, they're unsolicited so Rails never gets a chance to insert
  # the token.
  skip_before_filter :verify_authenticity_token

  def index
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
      #raise
    end
  end
  
end
