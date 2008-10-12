require 'etchserver'

class ResultsController < ApplicationController
  # Turn off this Rails security mechanism, as it is doesn't work in the
  # way this application works.  It expects POST requests to include a
  # token that it auto-inserts into forms, but our POST requests aren't
  # form data, they're unsolicited so Rails never gets a chance to insert
  # the token.
  skip_before_filter :verify_authenticity_token

  def index
    if !params.has_key?(:fqdn)
      render :text => 'fqdn parameter required', :status => :unprocessable_entity
      return
    end
    if !params.has_key?(:results) || !params.kind_of?(Array)
      render :text => 'results parameter required', :status => :unprocessable_entity
      return
    end
    client = Client.find_or_create_by_name(params[:fqdn])
    if client.nil?
      render :text "Unknown client", :status => :unprocessable_entity
      return
    end
    success_count = 0
    params[:results].each do |result|
      result = Result.new(:client => client, result)
      if result.save
        success_count += 1
      end
    end
    
    render :text => "Successfully recorded #{success_count} of #{params[:results].size} results"
  end
  
end
