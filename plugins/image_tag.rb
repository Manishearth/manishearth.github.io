# Title: Image tag with captions for Jekyll
# Authors: Brandon Mathis http://brandonmathis.com
#          Felix Schäfer, Frederic Hemberger
# Description: Easily output images with optional class names, width, height, title and alt attributes
#                     Use optional caption attribute to display title/alt text as caption
#
# Syntax {% img [class name(s)] [http[s]:/]/path/to/image [width [height]] [title text | "title text" ["alt text"]] %}
#
# Examples:
# {% img /images/ninja.png Ninja Attack! %}
# {% img left half http://site.com/images/ninja.png Ninja Attack! %}
# {% img left half http://site.com/images/ninja.png 150 150 "Ninja Attack!" "Ninja in attack posture" %}
#
# Output:
# <img src="/images/ninja.png">
# <img class="left half" src="http://site.com/images/ninja.png" title="Ninja Attack!" alt="Ninja Attack!">
# <img class="left half" src="http://site.com/images/ninja.png" width="150" height="150" title="Ninja Attack!" alt="Ninja in attack posture">

# Improvements from http://web.archive.org/web/20140625010305/http://blog.yvonet.com/2013/07/31/image-captions-with-octopress/

module Jekyll

  class ImageTag < Liquid::Tag
  @img = nil

    def initialize(tag_name, markup, tokens)
      attributes = ['class', 'src', 'width', 'height', 'title']

      if markup =~ /(?<class>[a-zA-Z ]*\s+)?(?<src>(?:https?:\/\/|\/|\S+\/)\S+)(?:\s+(?<width>\d+))?(?:\s+(?<height>\d+))?(?<title>\s+.+)?/i
        @img = attributes.reduce({}) { |img, attr| img[attr] = $~[attr].strip if $~[attr]; img }
        # if /(?:"|')(?<title>[^"']+)?(?:"|')\s+(?:"|')(?<alt>[^"']+)?(?:"|')/ =~ @img['title']
        #   @img['title']  = title
        #   @img['alt']    = alt
        # else
        #   @img['alt']    = @img['title'].gsub!(/"/, '&#34;') if @img['title']
        # end
        @img['alt'] = @img['title']
        @img['class'].gsub!(/"/, '') if @img['class']
      end
      super
    end

    def render(context)
      output = super
      if @img
        @img['src'] =~ /https?:\/\/[\S]+/ ? @imgsrc = @img['src'] : @imgsrc = "source" + @img['src']

        "<img #{@img.collect {|k,v| "#{k}=\"#{v}\"" if v}.join(" ")}>"
      else
        raise "Error processing input, expected syntax: {% img [class name(s)] /url/to/image [width height] [title text] %}"
      end
    end
  end

  class ImageBlock < Liquid::Block
  @img = nil

    def initialize(tag_name, markup, tokens)
      attributes = ['class', 'src', 'width', 'height', 'title']

      if markup =~ /(?<class>[a-zA-Z ]*\s+)?(?<src>(?:https?:\/\/|\/|\S+\/)\S+)(?:\s+(?<width>\d+))?(?:\s+(?<height>\d+))?(?<title>\s+.+)?/i
        @img = attributes.reduce({}) { |img, attr| img[attr] = $~[attr].strip if $~[attr]; img }
        # if /(?:"|')(?<title>[^"']+)?(?:"|')\s+(?:"|')(?<alt>[^"']+)?(?:"|')/ =~ @img['title']
        #   @img['title']  = title
        #   @img['alt']    = alt
        # else
        #   @img['alt']    = @img['title'].gsub!(/"/, '&#34;') if @img['title']
        # end
        @img['alt'] = @img['title']
        @img['class'].gsub!(/"/, '') if @img['class']
      end
      super
    end

    def render(context)
      output = super
      if @img
        @img['src'] =~ /https?:\/\/[\S]+/ ? @imgsrc = @img['src'] : @imgsrc = "source" + @img['src']
        if @img.has_key?("width")
          @imgwidth = @img['width']
        else
          raise "Captioned images must have width provided"
        end
        @imgclass = @img['class']
        @imgclass.slice!("captions")
        @img.delete("class")
        "<figure class=\"#{('caption-wrapper ' + @imgclass).rstrip}\" style=\"width: #{@imgwidth}px\">" +
          "<img class=\"caption\" #{@img.collect {|k,v| "#{k}=\"#{v}\"" if v}.join(" ")}>" +
          "<figcaption class=\"caption-text\">#{Kramdown::Document.new(output).to_html}</figcaption>" +
        "</figure>"
      else
        raise "Error processing input, expected syntax: {% imgcaption [class name(s)] /url/to/image [width height] [title text] %}"
      end
    end
  end
end

Liquid::Template.register_tag('img', Jekyll::ImageTag)
Liquid::Template.register_tag('imgcaption', Jekyll::ImageBlock)