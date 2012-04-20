require 'etch/server'

# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  # Verify that any changes are signed if the administrator has
  # enabled authentication
  before_filter :authenticate, :only => [:create, :update, :destroy]
  
  # This authentication system is targeted at etch clients.  There should be
  # an alternate authentication mechanism targeted at humans so that humans
  # can interact with this service when authentication is enabled.
  # https://sourceforge.net/apps/trac/etch/ticket/11
  def authenticate
    if Etch::Server.auth_enabled?
      if request.headers['Authorization'] &&
         request.headers['Authorization'] =~ /^EtchSignature /
        signature = request.headers['Authorization'].sub(/^EtchSignature /, '')
        verified = false
        begin
          verified = Etch::Server.verify_message(request.raw_post,
                                                 signature,
                                                 params)
        rescue Exception => e
          logger.error e.message
          logger.info e.backtrace.join("\n") if params[:debug]
          response = e.message
          response << e.backtrace.join("\n") if params[:debug]
          render :text => response, :status => :unauthorized
        end
      else
        logger.info "Authentication required, no authentication data found"
        render :text => "Authentication required, no authentication data found", :status => :unauthorized
      end
    end
  end
end
