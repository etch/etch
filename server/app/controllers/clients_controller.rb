require 'intmax'

class ClientsController < ApplicationController
  # GET /clients
  def index
    includes = {}

    sort = case params[:sort]
           when 'client'              then 'clients.name'
           when 'client_reverse'      then 'clients.name DESC'
           when 'status'              then 'clients.status'
           when 'status_reverse'      then 'clients.status DESC'
           when 'updated_at'          then 'clients.updated_at'
           when 'updated_at_reverse'  then 'clients.updated_at DESC'
           end
    # If a sort was not defined we'll make one default
    if sort.nil?
      params[:sort] = 'client'
      sort = 'clients.name'
    end
    
    # Parse all other params as search query args
    allowed_queries = ['name', 'status', 'updated_at']
    conditions_query = []
    conditions_values = []
    params.each_pair do |key, value|
      next if key == 'action'
      next if key == 'controller'
      next if key == 'format'
      next if key == 'page'
      next if key == 'sort'
      
      if key == 'health'
        if value == 'healthy'
          conditions_query << "status = 0 AND updated_at > ?"
          conditions_values << 24.hours.ago
        elsif value == 'broken'
          conditions_query << "status != 0 AND status != 200 AND updated_at > ?"
          conditions_values << 24.hours.ago
        elsif value == 'disabled'
          conditions_query << "status = 200 AND updated_at > ?"
          conditions_values << 24.hours.ago
        elsif value == 'stale'
          conditions_query << "updated_at <= ?"
          conditions_values << 24.hours.ago
        end
      elsif key == 'name_substring'
        conditions_query << "name LIKE ?"
        conditions_values << '%' + value + '%'
      elsif allowed_queries.include?(key)
        conditions_query << "#{key} = ?"
        conditions_values << value
      end
    end
    conditions_string = conditions_query.join(' AND ')
    
    per_page = Client.per_page # will_paginate's default value
    # Client's requesting XML get all entries
    respond_to { |format| format.html {}; format.xml { per_page = Integer::MAX } }
    
    @clients = Client.paginate(:all,
                               :include => includes,
                               :conditions => [ conditions_string, *conditions_values ],
                               :order => sort,
                               :page => params[:page],
                               :per_page => per_page)
    
    respond_to do |format|
      format.html # index.html.erb
      format.xml do
        render :xml => @clients.to_xml(:include => convert_includes(includes),
                                       :dasherize => false)
      end
    end
  end
  
  # GET /clients/1
  def show
    @timeline = nil
    if params[:timeline]
      @timeline = params[:timeline].to_i
    end

    @client = Client.find(params[:id])
    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @client.to_xml(:include => convert_includes(includes),
                                                  :dasherize => false) }
    end
  end
  
  # GET /clients/new
  def new
    @client = Client.new
    
    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @client }
    end
  end
  
  # GET /clients/1/edit
  def edit
    @client = Client.find(params[:id])
  end
  
  # POST /clients
  def create
    @client = Client.new(params[:client])
    
    respond_to do |format|
      if @client.save
        flash[:notice] = 'Client was successfully created.'
        format.html { redirect_to(@client) }
        format.xml  { render :xml => @client, :status => :created, :location => @client }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @client.errors, :status => :unprocessable_entity }
      end
    end
  end
  
  # PUT /clients/1
  def update
    @client = Client.find(params[:id])
    
    respond_to do |format|
      if @client.update_attributes(params[:client])
        flash[:notice] = 'Client was successfully updated.'
        format.html { redirect_to(@client) }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @client.errors, :status => :unprocessable_entity }
      end
    end
  end
  
  # DELETE /clients/1
  def destroy
    @client = Client.find(params[:id])
    @client.destroy
    
    respond_to do |format|
      format.html { redirect_to(clients_url) }
      format.xml  { head :ok }
    end
  end
end

