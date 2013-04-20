require 'intmax'

class ResultsController < ApplicationController
  # GET /results
  def index
    @combined = params[:combined]
    @query_string = request.query_string
    
    # Clients requesting XML get no pagination (all entries)
    per_page = Client.per_page # will_paginate's default value
    respond_to do |format|
      format.html {}
      format.xml { per_page = Integer::MAX }
    end
    # As do clients who specifically request everything
    if @combined
      per_page = Integer::MAX
    end
    
    @q = Result.search(params[:q])
    @results = @q.result.paginate(:page => params[:page], :per_page => per_page)
    
    respond_to do |format|
      format.html # index.html.erb
      format.xml do
        render :xml => @results.to_xml(:dasherize => false)
      end
    end
  end
  
  # GET /results/1
  def show
    @result = Result.find(params[:id])
    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @result.to_xml(:dasherize => false) }
    end
  end
  
  # GET /results/new
  def new
    @result = Result.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @result }
    end
  end

  # GET /results/1/edit
  def edit
    @result = Result.find(params[:id])
  end

  # POST /results
  def create
    if !params.has_key?(:fqdn)
      render :text => 'fqdn parameter required', :status => :unprocessable_entity
      return
    end
    if !params.has_key?(:status)
      render :text => 'status parameter required', :status => :unprocessable_entity
      return
    end
    if !params.has_key?(:results)
      # If the user didn't supply an array of individual file results then
      # insert an empty one so we don't have to keep checking for that
      # possibility later
      params[:results] = []
    elsif !params[:results].kind_of?(Array)
      render :text => 'results parameter must be supplied in array form', :status => :unprocessable_entity
      return
    end
    client = Client.find_or_create_by_name(params[:fqdn])
    if client.nil?
      render :text => "Unknown client", :status => :unprocessable_entity
      return
    end
    client.status = params[:status]
    client.message = params[:message]
    # This forces an update of updated_at even if status/message haven't
    # changed.  Otherwise clients will appear to go stale if their state
    # remains unchanged.
    client.updated_at = Time.now
    client.save
    
    success_count = 0
    params[:results].each do |result|
      # The Rails parameter parsing strips out parameters with empty values.
      # Most results will have a zero-length string in the 'message' field.
      # Rails will have stripped that, so we'll get nil when we fetch it,
      # but the Result model requires that message be defined.  In order to
      # save database space, replication bandwidth, etc. we don't want
      # to save successful results with no message, so only insert an empty
      # message into unsuccessful results.
      if !result[:success] && !result[:message]
        result[:message] = ''
      end
      
      # The message may have non-UTF8 characters, which will cause an error if
      # we try to save them to the database.  E.g. the file modified may not
      # be UTF-8, so the diff in the message might have non-UTF8 characters.
      # We don't know what the proper encoding should be (since we don't know
      # the encoding for arbitrary files that the user might manage), so just
      # force them to UTF-8.  Since ruby thinks the message is UTF-8 we have
      # to force it to transcode to another encoding and then back to UTF-8 to
      # detect and replace invalid bytes.
      result[:message].encode!('UTF-16', :invalid => :replace).encode!('UTF-8')
      
      result = Result.new(result.merge({:client => client}))
      if result.save
        success_count += 1
      end
    end
    
    render :text => "Successfully recorded #{success_count} of #{params[:results].size} results"
  end

  # PUT /results/1
  def update
    @result = Result.find(params[:id])

    respond_to do |format|
      if @result.update_attributes(params[:result])
        flash[:notice] = 'Result was successfully updated.'
        format.html { redirect_to(@result) }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @result.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /results/1
  def destroy
    @result = Result.find(params[:id])
    @result.destroy

    respond_to do |format|
      format.html { redirect_to(admin_results_url) }
      format.xml  { head :ok }
    end
  end
end

