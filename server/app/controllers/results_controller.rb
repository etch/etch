require 'intmax'

class ResultsController < ApplicationController
  # GET /results
  def index
    includes = {}
    
    # The index page uses clients.name, so always include it in the includes.
    # Otherwise there's a SQL lookup for each row
    includes[:client] = {}
    
    sort = case params[:sort]
           when 'client'                then includes[:client] = {}; 'clients.name'
           when 'client_reverse'        then includes[:client] = {}; 'clients.name DESC'
           when 'file'                  then 'results.file'
           when 'file_reverse'          then 'results.file DESC'
           when 'created_at'            then 'results.created_at'
           when 'created_at_reverse'    then 'results.created_at DESC'
           when 'success'               then 'results.success'
           when 'success_reverse'       then 'results.success DESC'
           when 'message_size'          then 'LENGTH(results.message)'
           when 'message_size_reverse'  then 'LENGTH(results.message) DESC'
           end
    # If a sort was not defined we'll make one default
    if sort.nil?
      params[:sort] = 'client'
      sort = 'clients.name'
      includes[:client] = {}
    end
    
    @combined = false
    if params[:combined]
      @combined = true
    end
    
    # Parse all other params as search query args
    allowed_queries = ['clients.id', 'clients.name', 'file', 'success']
    conditions_query = []
    conditions_values = []
    @query_params = []
    params.each_pair do |key, value|
      next if key == 'action'
      next if key == 'controller'
      next if key == 'format'
      next if key == 'page'
      @query_params << "#{key}=#{value}"  # Used by view
      next if key == 'sort'
      next if key == 'combined'
      
      if key == 'starttime'
        conditions_query << "results.created_at > ?"
        conditions_values << value.to_i.hours.ago
      elsif key == 'endtime'
        conditions_query << "results.created_at <= ?"
        conditions_values << value.to_i.hours.ago
      elsif allowed_queries.include?(key)
        conditions_query << "#{key} = ?"
        conditions_values << value
      end
    end
    conditions_string = conditions_query.join(' AND ')
    
    per_page = Result.per_page # will_paginate's default value
    # Client's requesting XML get all entries
    respond_to { |format| format.html {}; format.xml { per_page = Integer::MAX } }
    # As do clients who specifically request everything
    if @combined
      per_page = Integer::MAX
    end
    
    @results = Result.paginate(:all,
                               :include => includes,
                               :conditions => [ conditions_string, *conditions_values ],
                               :order => sort,
                               :page => params[:page],
                               :per_page => per_page)
    
    respond_to do |format|
      format.html # index.html.erb
      format.xml do
        render :xml => @results.to_xml(:include => convert_includes(includes),
                                       :dasherize => false)
      end
    end
  end
  
  # GET /results/1
  def show
    @result = Result.find(params[:id])
    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @result.to_xml(:include => convert_includes(includes),
                                                  :dasherize => false) }
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
    
    # NOTE:  This skips over the individual file results recording below
    # Re-enabled by jheiss, 7-July-2009  We have more disk space on the
    # servers now, we'll see if they can keep up
    #render :text => 'Client status recorded, individual file results recording disabled for now, jheiss, 9-May-2009'
    #return
    
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

