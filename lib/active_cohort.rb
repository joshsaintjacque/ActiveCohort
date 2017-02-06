# Public: Provides a cohort analysis of a set of ActiveRecord objects. Intended to be
# consumed by domain-specific classes, such AigAnalyst, OrderAnalyst, etc.
# See the constructor's documentation for information on the options hash.
#
# Examples
#
#   cohort = ActiveCohort.new(some_options_hash)
#   cohort.generate_report
#   # => [["", "Week 0", "Week 1", "Week 2", "Week 3", "Week 4", "Week 5"],
#        ["1/9", "27.0%", "8.1%", "2.7%", "0.0%", "0.0%", "0.0%"],
#        ["1/16", "37.9%", "7.6%", "0.0%", "0.0%", "0.0%"],
#        ["1/23", "42.2%", "3.1%", "0.0%", "0.0%"],
#        ["1/30", "31.8%", "0.0%", "0.0%"],
#        ["2/6", "-", "-"]]
#
#   puts cohort.to_csv
#   # => ,Week 0,Week 1,Week 2,Week 3,Week 4,Week 5
#        1/9,27.0%,8.1%,2.7%,0.0%,0.0%,0.0%
#        1/16,37.9%,7.6%,0.0%,0.0%,0.0%
#        1/23,42.2%,3.1%,0.0%,0.0%
#        1/30,31.8%,0.0%,0.0%
#        2/6,-,-
class ActiveCohort
  attr_accessor :subject_collection, :activation_lambda
  attr_writer   :start_at, :interval_timestamp_field

  # Public: Initialize a ActiveCohort.
  #
  # Required params
  #   subject_collection          - An ActiveRecord collection of records to perform a
  #                                 cohort analysis on.
  #   activation_lambda           - A lambda that returns a boolean indicating whether
  #                                 a given record has activated (e.g., converted,
  #                                 signed up, purchased, etc.)
  #   opts                        - A String naming the widget.
  #     start_at                  - The date at which to begin the analysis.
  #                                 Default: 30 days ago.
  #     interval                  - A string representation of the interval to run the analysis
  #                                 over (e.g, day, week, etc.) For instance, 'week' would
  #                                 result in a week-over-week analysis.
  #                                 Default: 'day'.
  #     interval_timestamp_field  - A String representation of the timestamp
  #                                 field on the cohort records to be used to
  #                                 offset between intervals.
  #                                 Default: 'created_at'.
  def initialize(subject_collection, activation_lambda, opts={})
    @subject_collection = subject_collection
    @activation_lambda = activation_lambda
    opts.each { |k,v| instance_variable_set("@#{k}", v) }
  end

  def interval
    @interval || 'day'
  end

  def interval=(interval)
    unless interval.downcase.in? valid_intervals
      raise "The interval \"#{interval}\" isn't valid.\n" +
            "Use #{valid_intervals.join ', '}"
    end
    @interval = interval.downcase
  end

  def start_at
    @start_at || 30.days.ago
  end

  def interval_timestamp_field
    @interval_timestamp_field || 'created_at'
  end

  # Public: Generates a cohort report using params supplied to the instance in
  # the constructor.
  #
  # Example
  #   cohort.generate_report
  #   # => [["", "Week 0", "Week 1", "Week 2", "Week 3", "Week 4", "Week 5"],
  #        ["1/9", "27.0%", "8.1%", "2.7%", "0.0%", "0.0%", "0.0%"],
  #        ["1/16", "37.9%", "7.6%", "0.0%", "0.0%", "0.0%"],
  #        ["1/23", "42.2%", "3.1%", "0.0%", "0.0%"],
  #        ["1/30", "31.8%", "0.0%", "0.0%"],
  #        ["2/6", "-", "-"]]
  #
  # Returns an Array of values representing the report.
  def generate_report
    validate_required_fields
    @report = []
    @report << header

    (number_of_intervals - 1).times do |row|
      @report << build_row(row)
    end
    @report
  end

  # Public: Outputs the cohort report in CSV format. Does not regenerate the
  # report if the instance has already generated it.
  #
  # Example
  #   puts cohort.to_csv
  #   # => ,Week 0,Week 1,Week 2,Week 3,Week 4,Week 5
  #        1/9,27.0%,8.1%,2.7%,0.0%,0.0%,0.0%
  #        1/16,37.9%,7.6%,0.0%,0.0%,0.0%
  #        1/23,42.2%,3.1%,0.0%,0.0%
  #        1/30,31.8%,0.0%,0.0%
  #        2/6,-,-
  #
  # Returns a String representation of the report with CSV formatting.
  def to_csv(seperator=',')
    report = @report || generate_report
    report.map{ |row| row.join(seperator) }.join("\n")
  end

  private
  def header
    header = ['']
    number_of_intervals.times do |i|
      header << "#{interval.capitalize} #{i}"
    end
    header
  end

  def number_of_intervals
    @interval == 'day' ? 30 : 6
  end

  def valid_intervals
    %w(day week month)
  end

  def assemble_cohort(start_date, end_date)
    @subject_collection.where(
      @interval_timestamp_field.to_sym => start_date..end_date
    )
  end

  def percentage_as_string(numerator, denominator)
    return "-" if denominator.zero?
    "#{((numerator / denominator.to_f) * 100).round(1)}%"
  end

  def start_date_for_cell(row, col)
    row_offset = row.send(:"#{interval}")
    col_offset = col.send(:"#{interval}")
    (start_at + row_offset + col_offset).send(:"beginning_of_#{interval}")
  end

  def build_row(row)
    row_values = []
    row_offset = row.send(:"#{interval}")
    cohort_start_date = (start_at + row_offset).send(:"beginning_of_#{interval}")
    cohort_end_date = cohort_start_date.send(:"end_of_#{interval}")
    cohort = assemble_cohort cohort_start_date, cohort_end_date
    row_values << cohort_start_date.strftime("%-m/%-d")
    (number_of_intervals - row).times do |col|
      activation_start_date = start_date_for_cell(row, col)
      activation_end_date = activation_start_date.send(:"end_of_#{interval}")
      activated = cohort.select { |c| @activation_lambda.call(c, activation_start_date, activation_end_date) }
      row_values << percentage_as_string(activated.length, cohort.length)
    end
    row_values
  end

  def validate_required_fields
    raise "Missing subject_collection" unless subject_collection.present?
    raise "Missing activation_lambda" unless activation_lambda.present?
  end
end