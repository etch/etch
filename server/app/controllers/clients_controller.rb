require 'intmax'

class ClientsController < ApplicationController
  # GET /clients
  def index
    # The dashboard has some custom search links for various health
    # categories.  If the user selected one then use the appropriate scope as
    # the starting point for further filtering rather than all clients.
    scope = nil
    case params['health']
    when 'healthy'
      scope = Client.healthy
    when 'broken'
      scope = Client.broken
    when 'disabled'
      scope = Client.disabled
    when 'stale'
      scope = Client.stale
    else
      scope = Client
    end
    
    # Clients requesting XML/JSON get no pagination (all entries)
    per_page = Client.per_page # will_paginate's default value
    respond_to do |format|
      format.html {}
      format.xml  { per_page = Integer::MAX }
      format.json { per_page = Integer::MAX }
    end
    
    @q = scope.search(params[:q])
    @clients = @q.result.paginate(:page => params[:page], :per_page => per_page)
    
    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @clients.to_xml(:dasherize => false) }
      format.json { render :json => @clients.to_json }
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
      format.xml  { render :xml => @client.to_xml(:dasherize => false) }
      format.json { render :json => @client.to_json }
    end
  end
  
  # GET /clients/new
  def new
    @client = Client.new
    
    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @client }
      format.json { render :json => @client }
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
        format.json { render :json => @client, :status => :created, :location => @client }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @client.errors, :status => :unprocessable_entity }
        format.json { render :json => @client.errors, :status => :unprocessable_entity }
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
        format.json { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @client.errors, :status => :unprocessable_entity }
        format.json { render :json => @client.errors, :status => :unprocessable_entity }
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
      format.json { head :ok }
    end
  end
end

