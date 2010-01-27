require 'date'

class DashboardController < ApplicationController
  def set_counts
    @total_count    = Client.count
    @healthy_count  = Client.count(:conditions => ["status = 0 AND updated_at > ?", 24.hours.ago])
    @broken_count   = Client.count(:conditions => ["status != 0 AND status != 200 AND updated_at > ?", 24.hours.ago])
    @disabled_count = Client.count(:conditions => ["status = 200 AND updated_at > ?", 24.hours.ago])
    @stale_count    = Client.count(:conditions => ["updated_at <= ?", 24.hours.ago])
  end
  def set_charts
    @status_chart = open_flash_chart_object(300, 300, url_for( :action => 'chart', :chart => 'status', :format => :json ))
    @client_chart = open_flash_chart_object(500, 300, url_for( :action => 'chart', :chart => 'client', :format => :json ))
  end
  
  def index
    set_counts
    set_charts
  end
  
  def chart
    respond_to do |format|
      format.html {
        set_charts
        case params[:chart]
        when 'status'
          render :partial => 'status_chart', :layout => false
          return
        when 'client'
          render :partial => 'client_chart', :layout => false
          return
        end
      }
      format.json {
        case params[:chart]
        when 'status'
          pie = Pie.new
          pie.start_angle = 0
          pie.animate = true
          pie.tooltip = '#label# of #total#'
          pie.colours = ['#36E728', '#D01F1F', '#E9F11D', '#741FD0']
          set_counts
          pie.values  = [PieValue.new(@healthy_count,  @healthy_count  == 0 ? '' : "Healthy: #{@healthy_count}"),
                         PieValue.new(@broken_count,   @broken_count   == 0 ? '' : "Broken: #{@broken_count}"),
                         PieValue.new(@disabled_count, @disabled_count == 0 ? '' : "Disabled: #{@disabled_count}"),
                         PieValue.new(@stale_count,    @stale_count    == 0 ? '' : "Stale: #{@stale_count}")]
          
          title = Title.new("Client Status")
          title.set_style('{font-size: 20px; color: #778877}')
          
          chart = OpenFlashChart.new
          chart.title = title
          chart.add_element(pie)
          chart.bg_colour = '#FFFFFF'
          
          chart.x_axis = nil
          
          render :text => chart, :layout => false
          return
        when 'client'
          clients = []
          months = []
          oldest = Client.find(:first, :order => 'created_at')
          if oldest
            start = Date.new(oldest.created_at.year, oldest.created_at.month, 1)
            next_month = Date.new(Time.now.year, Time.now.month, 1).next_month
            month = start
            while month != next_month
              # Combination of next_month and -1 gets us the last second of the month
              monthtime = Time.local(month.next_month.year, month.next_month.month) - 1
              clients << Client.count(:conditions => ["created_at <= ?", monthtime])
              months << "#{monthtime.strftime('%b')}\n#{monthtime.year}"
              month = month.next_month
            end
          end
          
          line_dot = LineDot.new
          line_dot.text = "Clients"
          line_dot.width = 1
          line_dot.colour = '#6363AC'
          line_dot.dot_size = 5
          line_dot.values = clients
          
          x = XAxis.new
          x.set_labels(months)
          
          y = YAxis.new
          # Set the top of the y scale to be the largest number of clients
          # rounded up to the nearest 10
          ymax = (clients.max.to_f / 10).ceil * 10
          ymax = 10 if ymax == 0  # In case there are no clients
          # Something around 10 divisions on the y axis looks decent
          ydiv = (ymax / 10).ceil
          y.set_range(0, ymax, ydiv)
          
          title = Title.new("Number of Clients")
          title.set_style('{font-size: 20px; color: #778877}')
          
          chart = OpenFlashChart.new
          chart.set_title(title)
          chart.x_axis = x
          chart.y_axis = y
          chart.bg_colour = '#FFFFFF'
          
          chart.add_element(line_dot)
          
          render :text => chart.to_s
          return
        end
      }
    end
  end
end

