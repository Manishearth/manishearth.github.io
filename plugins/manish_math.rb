# Input:
#   {% verbatim tag:p %}
#   $$a_1, a_2, a_3, \ldots$$
#   {% endverbatim %}
#
# Output:
#   <p>$$a_1, a_2, a_3, \ldots$$</p>
#
# Author: Hiroshi Yuki.
# Description: The content between {% verbatim %} and {% endverbatim %} would be rendered 'as is'.
# You can use 'tag' option to wrap the content.
# Purpose: To protect LaTeX (MathJax) content from markdown converter.
#
# Modified by Manish with explicit math support


module Jekyll
  def self.safe_wrap(input)
    "<div class='bogus-wrapper'><notextile>#{input}</notextile></div>"
  end
  class VerbatimBlock < Liquid::Block
    LEFT = ""
    RIGHT = ""

    def initialize(tag_name, markup, tokens)
      @tag = nil
      if markup =~ /\s*tag:(\S+)/i
        @tag = $1
        markup = markup.sub(/\s*tag:(\S+)/i,'')
      end
      super
    end

    def render(context)
      output = super
      content = ""
      content += "<#{@tag}>" if @tag
      content += Jekyll.safe_wrap(self.class::LEFT + output + self.class::RIGHT)
      content += "</#{@tag}>" if @tag
      return content
    end
  end
  class MathBlock < VerbatimBlock
    LEFT = "\\\\("
    RIGHT = "\\\\)"
  end
  class MMathBlock < VerbatimBlock
    LEFT = "$$"
    RIGHT = "$$"
  end
  class MathyBlock < Liquid::Block
    def render(context)
      output = super
      output = output.gsub(/\$\$([^$]*)\$\$/) { |s| Jekyll.safe_wrap("\\\\[" + Regexp.last_match[1] + "\\\\]")}
      output = output.gsub(/\$([^$]*)\$/)  { |s| Jekyll.safe_wrap("\\\\(" + Regexp.last_match[1] + "\\\\)")}
      return output
    end
  end
end

Liquid::Template.register_tag('verbatim', Jekyll::VerbatimBlock)
Liquid::Template.register_tag('m', Jekyll::MathBlock)
Liquid::Template.register_tag('mm', Jekyll::MMathBlock)
Liquid::Template.register_tag('mathy', Jekyll::MathyBlock)
