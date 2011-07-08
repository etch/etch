require 'test/unit'
require 'tempfile'
$:.unshift("#{File.dirname(File.expand_path(__FILE__))}/../../server/lib")
require 'etch'

# Test the XML abstraction methods in etch.rb

class TestXMLAbstraction < Test::Unit::TestCase
  def test_xmlnewdoc
    puts "Etch is using XML library: " + Etch.xmllib.to_s
    case Etch.xmllib
    when :libxml
      assert_kind_of(LibXML::XML::Document, Etch.xmlnewdoc)
    when :nokogiri
      assert_kind_of(Nokogiri::XML::Document, Etch.xmlnewdoc)
    when :rexml
      assert_kind_of(REXML::Document, Etch.xmlnewdoc)
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  def test_xmlroot_and_xmlsetroot
    doc = Etch.xmlnewdoc
    Etch.xmlsetroot(doc, Etch.xmlnewelem('root', doc))
    case Etch.xmllib
    when :libxml
      assert_kind_of(LibXML::XML::Node, Etch.xmlroot(doc))
      assert_equal('root', Etch.xmlroot(doc).name)
    when :nokogiri
      assert_kind_of(Nokogiri::XML::Node, Etch.xmlroot(doc))
      assert_equal('root', Etch.xmlroot(doc).name)
    when :rexml
      assert_kind_of(REXML::Node, Etch.xmlroot(doc))
      assert_equal('root', Etch.xmlroot(doc).name)
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  def test_xmlload
    goodfile = Tempfile.new('etch_xml_abstraction')
    goodfile.puts '<root><element/></root>'
    goodfile.close
    doc = Etch.xmlload(goodfile.path)
    badfile = Tempfile.new('etch_xml_abstraction')
    badfile.puts '<badroot>'
    badfile.close
    case Etch.xmllib
    when :libxml
      assert_kind_of(LibXML::XML::Node, Etch.xmlroot(doc))
      assert_equal('root', Etch.xmlroot(doc).name)
      assert_raises(LibXML::XML::Error) { Etch.xmlload(badfile.path) }
    when :nokogiri
      assert_kind_of(Nokogiri::XML::Node, Etch.xmlroot(doc))
      assert_equal('root', Etch.xmlroot(doc).name)
      assert_raises(Nokogiri::XML::SyntaxError) { Etch.xmlload(badfile.path) }
    when :rexml
      assert_kind_of(REXML::Node, Etch.xmlroot(doc))
      assert_equal('root', Etch.xmlroot(doc).name)
      assert_raises(REXML::ParseException) { Etch.xmlload(badfile.path) }
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  def test_xmlloaddtd
    dtdfile = Tempfile.new('etch_xml_abstraction')
    dtdfile.puts '<!ELEMENT root (element)>'
    dtdfile.puts '<!ELEMENT element EMPTY>'
    dtdfile.close
    dtd = Etch.xmlloaddtd(dtdfile.path)
    case Etch.xmllib
    when :libxml
      assert_kind_of(LibXML::XML::Dtd, dtd)
    when :nokogiri
      assert_kind_of(Nokogiri::XML::DTD, dtd)
    when :rexml
      assert_nil(dtd)
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  def test_xmlvalidate
    goodfile = Tempfile.new('etch_xml_abstraction')
    goodfile.puts '<root><element/></root>'
    goodfile.close
    gooddoc = Etch.xmlload(goodfile.path)
    
    badfile = Tempfile.new('etch_xml_abstraction')
    badfile.puts '<root/>'
    badfile.close
    baddoc = Etch.xmlload(badfile.path)
    
    dtdfile = Tempfile.new('etch_xml_abstraction')
    dtdfile.puts '<!ELEMENT root (element)>'
    dtdfile.puts '<!ELEMENT element EMPTY>'
    dtdfile.close
    dtd = Etch.xmlloaddtd(dtdfile.path)
    
    case Etch.xmllib
    when :libxml
      assert(Etch.xmlvalidate(gooddoc, dtd))
      assert_raises(LibXML::XML::Error) { Etch.xmlvalidate(baddoc, dtd) }
    when :nokogiri
      assert(Etch.xmlvalidate(gooddoc, dtd))
      assert_raises(RuntimeError) { Etch.xmlvalidate(baddoc, dtd) }
    when :rexml
      # REXML doesn't support validation, xmlvalidate will always return true
      assert(Etch.xmlvalidate(gooddoc, dtd))
      assert(Etch.xmlvalidate(baddoc, dtd))
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  def test_xmlnewelem
    doc = Etch.xmlnewdoc
    elem = Etch.xmlnewelem('element', doc)
    case Etch.xmllib
    when :libxml
      assert_kind_of(LibXML::XML::Node, elem)
      assert_equal('element', elem.name)
    when :nokogiri
      assert_kind_of(Nokogiri::XML::Element, elem)
      assert_equal('element', elem.name)
    when :rexml
      assert_kind_of(REXML::Element, elem)
      assert_equal('element', elem.name)
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  def test_xmleach
    file = Tempfile.new('etch_xml_abstraction')
    file.puts '<root><element/><element/><other/></root>'
    file.close
    doc = Etch.xmlload(file.path)
    
    counter = 0
    Etch.xmleach(doc, '/root/element') do |elem|
      counter += 1
      case Etch.xmllib
      when :libxml
        assert_kind_of(LibXML::XML::Node, elem)
        assert_equal('element', elem.name)
      when :nokogiri
        assert_kind_of(Nokogiri::XML::Element, elem)
        assert_equal('element', elem.name)
      when :rexml
        assert_kind_of(REXML::Element, elem)
        assert_equal('element', elem.name)
      else
        raise "Unknown XML library #{Etch.xmllib}"
      end
    end
    assert_equal(2, counter)
  end
  def test_xmleachall
    file = Tempfile.new('etch_xml_abstraction')
    file.puts '<root><element><child/><otherchild/></element><element/><other/></root>'
    file.close
    doc = Etch.xmlload(file.path)
    
    counter = 0
    Etch.xmleachall(doc) do |elem|
      counter += 1
      case Etch.xmllib
      when :libxml
        assert_kind_of(LibXML::XML::Node, elem)
        assert(['element', 'other'].include?(elem.name))
      when :nokogiri
        assert_kind_of(Nokogiri::XML::Element, elem)
        assert(['element', 'other'].include?(elem.name))
      when :rexml
        assert_kind_of(REXML::Element, elem)
        assert(['element', 'other'].include?(elem.name))
      else
        raise "Unknown XML library #{Etch.xmllib}"
      end
    end
    assert_equal(3, counter)
    
    counter = 0
    Etch.xmleachall(Etch.xmlfindfirst(doc, '/root/element')) do |elem|
      counter += 1
      case Etch.xmllib
      when :libxml
        assert_kind_of(LibXML::XML::Node, elem)
        assert(['child', 'otherchild'].include?(elem.name))
      when :nokogiri
        assert_kind_of(Nokogiri::XML::Element, elem)
        assert(['child', 'otherchild'].include?(elem.name))
      when :rexml
        assert_kind_of(REXML::Element, elem)
        assert(['child', 'otherchild'].include?(elem.name))
      else
        raise "Unknown XML library #{Etch.xmllib}"
      end
    end
    assert_equal(2, counter)
    
  end
  def test_xmleachattrall
    file = Tempfile.new('etch_xml_abstraction')
    file.puts '<root attrone="foo" attrtwo="bar"/>'
    file.close
    doc = Etch.xmlload(file.path)
    
    counter = 0
    Etch.xmleachattrall(doc.root) do |attr|
      counter += 1
      case Etch.xmllib
      when :libxml
        assert_kind_of(LibXML::XML::Attr, attr)
        assert(['attrone', 'attrtwo'].include?(attr.name))
      when :nokogiri
        assert_kind_of(Nokogiri::XML::Attr, attr)
        assert(['attrone', 'attrtwo'].include?(attr.name))
      when :rexml
        assert_kind_of(REXML::Attribute, attr)
        assert(['attrone', 'attrtwo'].include?(attr.name))
      else
        raise "Unknown XML library #{Etch.xmllib}"
      end
    end
    assert_equal(2, counter)
  end
  def test_xmlarray
    file = Tempfile.new('etch_xml_abstraction')
    file.puts '<root><element/><element/><other/></root>'
    file.close
    doc = Etch.xmlload(file.path)
    
    assert_kind_of(Array, Etch.xmlarray(doc, '/root/*'))
    assert_equal(3, Etch.xmlarray(doc, '/root/*').length)
    
    assert_kind_of(Array, Etch.xmlarray(doc, '/root/element'))
    assert_equal(2, Etch.xmlarray(doc, '/root/element').length)
    
    assert_kind_of(Array, Etch.xmlarray(doc, '/root/bogus'))
    assert_equal(0, Etch.xmlarray(doc, '/root/bogus').length)
    
    Etch.xmlarray(doc, '/root/*').each do |elem|
      case Etch.xmllib
      when :libxml
        assert_kind_of(LibXML::XML::Node, elem)
        assert(['element', 'other'].include?(elem.name))
      when :nokogiri
        assert_kind_of(Nokogiri::XML::Element, elem)
        assert(['element', 'other'].include?(elem.name))
      when :rexml
        assert_kind_of(REXML::Element, elem)
        assert(['element', 'other'].include?(elem.name))
      else
        raise "Unknown XML library #{Etch.xmllib}"
      end
    end
  end
  def test_xmlfindfirst
    file = Tempfile.new('etch_xml_abstraction')
    file.puts '<root><element><child/><otherchild/></element><element/><other/></root>'
    file.close
    doc = Etch.xmlload(file.path)
    
    elem = Etch.xmlfindfirst(doc, '/root/element')
    case Etch.xmllib
    when :libxml
      assert_kind_of(LibXML::XML::Node, elem)
      assert_equal('element', elem.name)
      # This ensures we got the first <element> and not the second
      assert_equal(2, elem.children.length)
    when :nokogiri
      assert_kind_of(Nokogiri::XML::Element, elem)
      assert_equal('element', elem.name)
      # This ensures we got the first <element> and not the second
      assert_equal(2, elem.children.length)
    when :rexml
      assert_kind_of(REXML::Element, elem)
      assert_equal('element', elem.name)
      # This ensures we got the first <element> and not the second
      assert_equal(2, elem.children.length)
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
    # We have code that assumes xmlfindfirst returns a false value when
    # queried for non-existent elements
    assert(!Etch.xmlfindfirst(doc, '/not_an_element'))
  end
  def test_xmltext
    file = Tempfile.new('etch_xml_abstraction')
    file.puts '<root><element>some text</element><other/></root>'
    file.close
    doc = Etch.xmlload(file.path)
    
    assert_equal('some text', Etch.xmltext(Etch.xmlfindfirst(doc, '/root/element')))
    assert_equal('', Etch.xmltext(Etch.xmlfindfirst(doc, '/root/other')))
  end
  def test_xmlsettext
    file = Tempfile.new('etch_xml_abstraction')
    file.puts '<root><element>some text</element><other/></root>'
    file.close
    doc = Etch.xmlload(file.path)
    
    Etch.xmlsettext(Etch.xmlfindfirst(doc, '/root/element'), 'new text')
    assert_equal('new text', Etch.xmltext(Etch.xmlfindfirst(doc, '/root/element')))
    Etch.xmlsettext(Etch.xmlfindfirst(doc, '/root/other'), 'other text')
    assert_equal('other text', Etch.xmltext(Etch.xmlfindfirst(doc, '/root/other')))
  end
  def test_xmladd
    file = Tempfile.new('etch_xml_abstraction')
    file.puts '<root><element/></root>'
    file.close
    doc = Etch.xmlload(file.path)
    
    Etch.xmladd(doc, '/root/element', 'childone')
    Etch.xmladd(doc, '/root/element', 'childtwo', 'some text')
    childone = Etch.xmlfindfirst(doc, '/root/element/childone')
    childtwo = Etch.xmlfindfirst(doc, '/root/element/childtwo')
    case Etch.xmllib
    when :libxml
      assert_kind_of(LibXML::XML::Node, childone)
      assert_equal('childone', childone.name)
      assert_equal('', Etch.xmltext(childone))
      assert_kind_of(LibXML::XML::Node, childtwo)
      assert_equal('childtwo', childtwo.name)
      assert_equal('some text', Etch.xmltext(childtwo))
    when :nokogiri
      assert_kind_of(Nokogiri::XML::Element, childone)
      assert_equal('childone', childone.name)
      assert_equal('', Etch.xmltext(childone))
      assert_kind_of(Nokogiri::XML::Element, childtwo)
      assert_equal('childtwo', childtwo.name)
      assert_equal('some text', Etch.xmltext(childtwo))
    when :rexml
      assert_kind_of(REXML::Element, childone)
      assert_equal('childone', childone.name)
      assert_equal('', Etch.xmltext(childone))
      assert_kind_of(REXML::Element, childtwo)
      assert_equal('childtwo', childtwo.name)
      assert_equal('some text', Etch.xmltext(childtwo))
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  def test_xmlcopyelem
    file = Tempfile.new('etch_xml_abstraction')
    file.puts '<root><element><child/></element><other/></root>'
    file.close
    doc = Etch.xmlload(file.path)
    
    original = Etch.xmlfindfirst(doc, '/root/element/child')
    Etch.xmlcopyelem(original, Etch.xmlfindfirst(doc, '/root/other'))
    copy = Etch.xmlfindfirst(doc, '/root/other/child')
    # Change the child so that we can test that it is separate from the orignal
    Etch.xmlsettext(copy, 'some text')
    case Etch.xmllib
    when :libxml
      assert_kind_of(LibXML::XML::Node, original)
      assert_kind_of(LibXML::XML::Node, copy)
      assert_equal('child', original.name)
      assert_equal('', Etch.xmltext(original))
      assert_equal('child', copy.name)
      assert_equal('some text', Etch.xmltext(copy))
    when :nokogiri
      assert_kind_of(Nokogiri::XML::Element, original)
      assert_kind_of(Nokogiri::XML::Element, copy)
      assert_equal('child', original.name)
      assert_equal('', Etch.xmltext(original))
      assert_equal('child', copy.name)
      assert_equal('some text', Etch.xmltext(copy))
    when :rexml
      assert_kind_of(REXML::Element, original)
      assert_kind_of(REXML::Element, copy)
      assert_equal('child', original.name)
      assert_equal('', Etch.xmltext(original))
      assert_equal('child', copy.name)
      assert_equal('some text', Etch.xmltext(copy))
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  def test_xmlremove
    file = Tempfile.new('etch_xml_abstraction')
    file.puts '<root><element><child/></element><other/></root>'
    file.close
    doc = Etch.xmlload(file.path)
    
    Etch.xmlremove(doc, Etch.xmlfindfirst(doc, '/root/element'))
    assert_nil(Etch.xmlfindfirst(doc, '/root/element'))
    case Etch.xmllib
    when :libxml
      assert_kind_of(LibXML::XML::Node, Etch.xmlfindfirst(doc, '/root/other'))
    when :nokogiri
      assert_kind_of(Nokogiri::XML::Element, Etch.xmlfindfirst(doc, '/root/other'))
    when :rexml
      assert_kind_of(REXML::Element, Etch.xmlfindfirst(doc, '/root/other'))
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  def test_xmlremovepath
    file = Tempfile.new('etch_xml_abstraction')
    file.puts '<root><element><child/></element><element/><other/></root>'
    file.close
    doc = Etch.xmlload(file.path)
    
    Etch.xmlremovepath(doc, '/root/element')
    assert_nil(Etch.xmlfindfirst(doc, '/root/element'))
    case Etch.xmllib
    when :libxml
      assert_kind_of(LibXML::XML::Node, Etch.xmlfindfirst(doc, '/root/other'))
    when :nokogiri
      assert_kind_of(Nokogiri::XML::Element, Etch.xmlfindfirst(doc, '/root/other'))
    when :rexml
      assert_kind_of(REXML::Element, Etch.xmlfindfirst(doc, '/root/other'))
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  def test_xmlattradd
    file = Tempfile.new('etch_xml_abstraction')
    file.puts '<root><element><child/></element><element/><other/></root>'
    file.close
    doc = Etch.xmlload(file.path)
    
    first = Etch.xmlarray(doc, '/root/element').first
    second = Etch.xmlarray(doc, '/root/element').last
    Etch.xmlattradd(first, 'attrname', 'attrvalue')
    case Etch.xmllib
    when :libxml
      assert_equal('attrvalue', first.attributes['attrname'])
      assert_nil(second.attributes['attrname'])
    when :nokogiri
      assert_equal('attrvalue', first['attrname'])
      assert_nil(second['attrname'])
    when :rexml
      assert_equal('attrvalue', first.attributes['attrname'])
      assert_nil(second.attributes['attrname'])
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
  def test_xmlattrvalue
    file = Tempfile.new('etch_xml_abstraction')
    file.puts '<root><element attrname="attrvalue"><child/></element><element attrname="othervalue"/><other/></root>'
    file.close
    doc = Etch.xmlload(file.path)
    
    first = Etch.xmlarray(doc, '/root/element').first
    second = Etch.xmlarray(doc, '/root/element').last
    assert_equal('attrvalue', Etch.xmlattrvalue(first, 'attrname'))
    assert_equal('othervalue', Etch.xmlattrvalue(second, 'attrname'))
  end
  def test_xmlattrremove
    file = Tempfile.new('etch_xml_abstraction')
    file.puts '<root><element attrname="attrvalue"><child/></element><element attrname="othervalue"/><other/></root>'
    file.close
    doc = Etch.xmlload(file.path)
    
    first = Etch.xmlarray(doc, '/root/element').first
    second = Etch.xmlarray(doc, '/root/element').last
    
    Etch.xmleachattrall(first) do |attr|
      Etch.xmlattrremove(first, attr)
    end
    
    case Etch.xmllib
    when :libxml
      assert_nil(first.attributes['attrname'])
      assert_equal('othervalue', second.attributes['attrname'])
    when :nokogiri
      assert_nil(first['attrname'])
      assert_equal('othervalue', second['attrname'])
    when :rexml
      assert_nil(first.attributes['attrname'])
      assert_equal('othervalue', second.attributes['attrname'])
    else
      raise "Unknown XML library #{Etch.xmllib}"
    end
  end
end

