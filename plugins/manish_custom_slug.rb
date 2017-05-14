# module Jekyll
#     class PermalinkRewriter < Generator
#         safe true
#         priority :low

#         def generate(site)
#             site.posts.each do |item|
#                 # item.data['permalink'] = '/blog/' + ("%.2d" % item.date.year) + '/' + ("%.2d" % item.date.month) + '/' + ("%.2d" % item.date.day) + '/' + item.slug + '/'
#             end
#         end
#     end
# end

module SafeYAML
  class Parse
    class Date
      def self.value(value)
        a = DateTime.parse(value)
        # Strip out timezone info by converting to a date first
        a.to_date.to_time
      end
    end
  end
end
