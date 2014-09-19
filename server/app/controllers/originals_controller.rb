require 'intmax'

class OriginalsController < ApplicationController
  # GET /originals
  def index
    # Clients requesting XML/JSON get no pagination (all entries)
    per_page = Original.per_page # will_paginate's default value
    respond_to do |format|
      format.html {}
      format.xml  { per_page = Integer::MAX }
      format.json { per_page = Integer::MAX }
    end
    
    @q = Original.search(params[:q])
    @originals = @q.result.paginate(:page => params[:page], :per_page => per_page)
    
    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @originals.to_xml(:dasherize => false) }
      format.json { render :json => @originals }
    end
  end

  # GET /originals/1
  def show
    @original = Original.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @original.to_xml(:dasherize => false) }
      format.json { render :json => @original }
    end
  end

  # GET /originals/new
  def new
    @original = Original.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @original.to_xml(:dasherize => false) }
      format.json { render :json => @original }
    end
  end

  # GET /originals/1/edit
  def edit
    @original = Original.find(params[:id])
  end

  # POST /originals
  def create
    @original = Original.new(original_params)

    respond_to do |format|
      if @original.save
        flash[:notice] = 'Original was successfully created.'
        format.html { redirect_to(@original) }
        format.xml  { render :xml => @original.to_xml(:dasherize => false), :status => :created, :location => @original }
        format.json { render :json => @original, :status => :created, :location => @original }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @original.errors, :status => :unprocessable_entity }
        format.json { render :json => @original.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /originals/1
  def update
    @original = Original.find(params[:id])

    respond_to do |format|
      if @original.update_attributes(original_params)
        flash[:notice] = 'Original was successfully updated.'
        format.html { redirect_to(@original) }
        format.xml  { head :ok }
        format.json { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @original.errors, :status => :unprocessable_entity }
        format.json { render :json => @original.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /originals/1
  def destroy
    @original = Original.find(params[:id])
    @original.destroy

    respond_to do |format|
      format.html { redirect_to(originals_url) }
      format.xml  { head :ok }
      format.json { head :ok }
    end
  end

  private
    def original_params
      params.require(:original).permit(:client_id, :file, :sum)
    end
end
