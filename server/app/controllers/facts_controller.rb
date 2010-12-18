require 'intmax'

class FactsController < ApplicationController
  # GET /facts
  def index
    # Clients requesting XML get no pagination (all entries)
    per_page = Fact.per_page # will_paginate's default value
    respond_to do |format|
      format.html {}
      format.xml { per_page = Integer::MAX }
    end
    
    @search = Fact.search(params[:search])
    @facts = @search.paginate(:page => params[:page], :per_page => per_page)
    
    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @facts }
    end
  end

  # GET /facts/1
  def show
    @fact = Fact.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @fact }
    end
  end

  # GET /facts/new
  def new
    @fact = Fact.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @fact }
    end
  end

  # GET /facts/1/edit
  def edit
    @fact = Fact.find(params[:id])
  end

  # POST /facts
  def create
    @fact = Fact.new(params[:fact])

    respond_to do |format|
      if @fact.save
        flash[:notice] = 'Fact was successfully created.'
        format.html { redirect_to(@fact) }
        format.xml  { render :xml => @fact, :status => :created, :location => @fact }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @fact.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /facts/1
  def update
    @fact = Fact.find(params[:id])

    respond_to do |format|
      if @fact.update_attributes(params[:fact])
        flash[:notice] = 'Fact was successfully updated.'
        format.html { redirect_to(@fact) }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @fact.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /facts/1
  def destroy
    @fact = Fact.find(params[:id])
    @fact.destroy

    respond_to do |format|
      format.html { redirect_to(admin_facts_url) }
      format.xml  { head :ok }
    end
  end
end
