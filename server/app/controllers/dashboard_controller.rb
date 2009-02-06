class DashboardController < ApplicationController
  def index
    @total_count    = Client.count
    @healthy_count  = Client.count(:conditions => ["status = 0 AND updated_at > ?", 24.hours.ago])
    @broken_count   = Client.count(:conditions => ["status != 0 AND status != 200 AND updated_at > ?", 24.hours.ago])
    @disabled_count = Client.count(:conditions => ["status = 200 AND updated_at > ?", 24.hours.ago])
    @stale_count    = Client.count(:conditions => ["updated_at <= ?", 24.hours.ago])
    
    respond_to do |format|
      format.html {
        @status_graph = open_flash_chart_object(300, 300, url_for( :action => 'index', :graph => 'status', :format => :json ))
        @client_graph = open_flash_chart_object(500, 300, url_for( :action => 'index', :graph => 'client', :format => :json ))
      }
      format.json {
        case params[:graph]
        when 'status'
          pie = Pie.new
          pie.start_angle = 0
          pie.animate = true
          pie.tooltip = '#label# of #total#'
          pie.colours = ['#36E728', '#D01F1F', '#E9F11D', '#741FD0']
          pie.values  = [PieValue.new(@healthy_count,  @healthy_count  == 0 ? '' : "Healthy: #{@healthy_count}"),
                         PieValue.new(@broken_count,   @broken_count   == 0 ? '' : "Broken: #{@broken_count}"),
                         PieValue.new(@disabled_count, @disabled_count == 0 ? '' : "Disabled: #{@disabled_count}"),
                         PieValue.new(@stale_count,    @stale_count    == 0 ? '' : "Stale: #{@stale_count}")]
          
          title = Title.new("Client Status")
          
          chart = OpenFlashChart.new
          chart.title = title
          chart.add_element(pie)
          chart.bg_colour = '#FFFFFF'
          
          chart.x_axis = nil
          
          render :text => chart, :layout => false
        when 'client'
          clients = []
          months = []
          # Find the oldest client
          oldest = Client.find(:first, :order => 'created_at')
          # Get the month and year of that date
          month = oldest.created_at.mon
          year = oldest.created_at.year
          # Iterate months to present
          (year..Time.now.year).each do |y|
            start_month = 1
            end_month = 12
            if y == year
              start_month = month
            end
            if y == Time.now.year
              end_month = Time.now.month
            end
            (start_month..end_month).each do |m|
              end_time = nil
              if m == 12
                end_time = Time.local(y+1, 1)
              else
                end_time = Time.local(y, m+1)
              end
              # This should get us the last second of the desired month
              end_time - 1
              clients << Client.count(:conditions => ["created_at <= ?", end_time])
              months << end_time.strftime('%b %Y')
            end
          end
          
          line_dot = LineDot.new
          line_dot.text = "Clients"
          line_dot.width = 1
          line_dot.colour = '#6363AC'
          line_dot.dot_size = 5
          line_dot.values = clients
          
          tmp = []
          x_labels = XAxisLabels.new
          x_labels.set_vertical()
          months.each do |text|
            tmp << XAxisLabel.new(text, '#0000ff', 12, 'diagonal')
          end
          x_labels.labels = tmp
          x = XAxis.new
          x.set_labels(x_labels)
          
          y = YAxis.new
          # Set the top of the y scale to be the largest number of clients
          # rounded up to the nearest 10
          ymax = (clients.max.to_f / 10).ceil * 10
          ymax = 10 if ymax == 0  # In case there are no clients
          # Something around 10 divisions on the y axis looks decent
          ydiv = (ymax / 10).ceil
          y.set_range(0, ymax, ydiv)
          
          title = Title.new("Number of Clients")
          chart = OpenFlashChart.new
          chart.set_title(title)
          chart.x_axis = x
          chart.y_axis = y
          chart.bg_colour = '#FFFFFF'
          
          chart.add_element(line_dot)
          
          render :text => chart.to_s
        end
      }
    end
  end
end

