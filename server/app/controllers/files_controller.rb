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
      # params[:files] is a hash of filename => hash_of_options
      # The client runs the filename through CGI.escape in case it contains
      # special characters.  Older versions of Rails automatically decoded the
      # filename, but as of Rails 2.3 we need to do it ourself.
      files = params[:files].inject({}) { |h, (file, value)| h[CGI.unescape(file)] = value; h }
      response = etchserver.generate(files)
      render :text => response
    rescue Exception => e
      logger.error e.message
      logger.info e.backtrace.join("\n") if params[:debug]
      response = e.message + "\n"
      response << e.backtrace.join("\n") if params[:debug]
      render :text => response, :status => :internal_server_error
    end
  end
end
