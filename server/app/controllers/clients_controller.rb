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
    
    if conditions_query.empty?
      @clients = Client.paginate(:all,
                                 :include => includes,
                                 :order => sort,
                                 :page => params[:page])
    else
      conditions_string = conditions_query.join(' AND ')
      @clients = Client.paginate(:all,
                                 :include => includes,
                                 :conditions => [ conditions_string, *conditions_values ],
                                 :order => sort,
                                 :page => params[:page])
    end
  end
  
  # GET /clients/1
  def show
    @timeline = nil
    if params[:timeline]
      @timeline = params[:timeline].to_i
    end

    @client = Client.find(params[:id])
  end
end
