class EtchConfigsController < ApplicationController
  # GET /etch_configs
  def index
    @etch_configs = EtchConfig.find :all

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @etch_configs }
    end
  end

  # GET /etch_configs/1
  def show
    @etch_config = EtchConfig.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @etch_config }
    end
  end

  # GET /etch_configs/new
  def new
    @etch_config = EtchConfig.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @etch_config }
    end
  end

  # GET /etch_configs/1/edit
  def edit
    @etch_config = EtchConfig.find(params[:id])
  end

  # POST /etch_configs
  def create
    @etch_config = EtchConfig.new(params[:etch_config])

    respond_to do |format|
      if @etch_config.save
        flash[:notice] = 'EtchConfig was successfully created.'
        format.html { redirect_to(@etch_config) }
        format.xml  { render :xml => @etch_config, :status => :created, :location => @etch_config }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @etch_config.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /etch_configs/1
  def update
    @etch_config = EtchConfig.find(params[:id])

    respond_to do |format|
      if @etch_config.update_attributes(params[:etch_config])
        flash[:notice] = 'EtchConfig was successfully updated.'
        format.html { redirect_to(@etch_config) }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @etch_config.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /etch_configs/1
  def destroy
    @etch_config = EtchConfig.find(params[:id])
    @etch_config.destroy

    respond_to do |format|
      format.html { redirect_to(admin_etch_configs_url) }
      format.xml  { head :ok }
    end
  end
end
