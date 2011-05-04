require 'etch/server'

# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  helper :all # include all helpers, all the time

  # See ActionController::Base for details 
  # Uncomment this to filter the contents of submitted sensitive data parameters
  # from your application log (in this case, all fields with names like "password"). 
  # filter_parameter_logging :password

  # Turn on the exception_notification plugin
  # See environment.rb for the email address(s) to which exceptions are mailed
  include ExceptionNotifiable

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
  
  # find and to_xml take their :include options in different formats
  # find wants:
  # :include => { :rack => { :datacenter_rack_assignment => :datacenter } }
  # or this (which is what we use because it is easier to generate recursively)
  # :include => { :rack => { :datacenter_rack_assignment => { :datacenter => {} } } }
  # to_xml wants:
  # :include => { :rack => { :include => { :datacenter_rack_assignment => { :include => { :datacenter => {} } } } } }
  # This method takes the find format and returns the to_xml format
  def convert_includes(includes)
    includes.each do |key, value|
      unless (value.nil? || value.blank?)
        includes[key] = { :include => convert_includes(value) }
      end
    end
    includes
  end
end
