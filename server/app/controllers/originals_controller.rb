class OriginalsController < ApplicationController
  # GET /originals
  def index
    @originals = Original.find :all

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @originals }
    end
  end

  # GET /originals/1
  def show
    @original = Original.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @original }
    end
  end

  # GET /originals/new
  def new
    @original = Original.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @original }
    end
  end

  # GET /originals/1/edit
  def edit
    @original = Original.find(params[:id])
  end

  # POST /originals
  def create
    @original = Original.new(params[:original])

    respond_to do |format|
      if @original.save
        flash[:notice] = 'Original was successfully created.'
        format.html { redirect_to(@original) }
        format.xml  { render :xml => @original, :status => :created, :location => @original }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @original.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /originals/1
  def update
    @original = Original.find(params[:id])

    respond_to do |format|
      if @original.update_attributes(params[:original])
        flash[:notice] = 'Original was successfully updated.'
        format.html { redirect_to(@original) }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @original.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /originals/1
  def destroy
    @original = Original.find(params[:id])
    @original.destroy

    respond_to do |format|
      format.html { redirect_to(admin_originals_url) }
      format.xml  { head :ok }
    end
  end
end
