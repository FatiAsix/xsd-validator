require "xsd/validator/version"
require 'nokogiri'

module Xsd
  module Validator
    SII_LR = "https://www2.agenciatributaria.gob.es/static_files/common/internet/dep/aplicaciones/es/aeat/ssii/fact/ws/SuministroLR.xsd"
    SII_INFORMACION = "https://www2.agenciatributaria.gob.es/static_files/common/internet/dep/aplicaciones/es/aeat/ssii/fact/ws/SuministroInformacion.xsd"
    GIPUZKOA_SII_LR = "https://egoitza.gipuzkoa.eus/ogasuna/sii/ficheros/SuministroLR.xsd"
    GIPUZKOA_SII_INFORMACION = "https://egoitza.gipuzkoa.eus/ogasuna/sii/ficheros/SuministroInformacion.xsd"
    BIZKAIA_SII_LR = "http://www.bizkaia.eus/ogasuna/sii/documentos/SuministroLR.xsd"
    BIZKAIA_SII_INFORMACION = "http://www.bizkaia.eus/ogasuna/sii/documentos/SuministroInformacion.xsd"

    UBL_DOCUMENT = /urn:oasis:names:specification:ubl:schema:xsd:/
    CII_DOCUMENT = /urn:un:unece:uncefact:data:standard:CrossIndustryInvoice/
    RAM = "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100"

    class ValidationError < RuntimeError
    end

    def xsd_validate(doc)
      doc=Nokogiri::XML(doc) unless doc.is_a? Nokogiri::XML::Document
      xsd_path=root_namespace_xsd(doc)
      puts doc if xsd_path.nil?
      xsd_file = File.open(xsd_path,'rb')
      xsd = Nokogiri::XML::Schema(xsd_file)
      xsd.validate(doc)
    end

    def xsd_validate!(doc)
      errors = xsd_validate(doc)
      raise ValidationError.new(errors.join("\n")) if errors.any?
      return true
    end

    def root_namespace(doc)
      doc=Nokogiri::XML(doc) unless doc.is_a? Nokogiri::XML::Document
      if doc.root.nil?
        raise StandardError.new("Is not a valid XML")
      elsif doc.root.namespace.nil?
        raise StandardError.new("XML does not have a root namespace")
      else
        doc.root.namespace.href
      end
    end

    def root_namespace_xsd(doc)
      doc=Nokogiri::XML(doc) unless doc.is_a? Nokogiri::XML::Document
      namespace = root_namespace(doc)
      case namespace
      when SII_LR
        case doc.xpath('//sii:Cabecera/sii:IDVersionSii', sii: SII_INFORMACION).text
        when '1.1'
          schema_path('sii_v11/SuministroLR.xsd')
        when '1.0'
          schema_path('sii_v10/SuministroLR.xsd')
        when '0.7'
          schema_path('sii_v07/SuministroLR.xsd')
        else
          schema_path('sii_v06/SuministroLR.xsd')
        end
      when GIPUZKOA_SII_LR
        case doc.xpath('//sii:Cabecera/sii:IDVersionSii', sii: GIPUZKOA_SII_INFORMACION).text
        when '1.0'
          schema_path('sii_gipuzkoa/SuministroLR.xsd')
        else
          schema_path('sii_gipuzkoa/v11/SuministroLR.xsd')
        end
      when BIZKAIA_SII_LR
        case doc.xpath('//sii:Cabecera/sii:IDVersionSii', sii: BIZKAIA_SII_INFORMACION).text
        when '1.0'
          schema_path('sii_bizkaia/SuministroLR.xsd')
        else
          schema_path('sii_bizkaia/v11/SuministroLR.xsd')
        end
      when UBL_DOCUMENT
        # eSPap uses the same namespace as UBL :(
        case doc.xpath('//cbc:CustomizationID', cbc: "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2").text
        when 'UBL-2.1-eSPap'
          schema_path('espap/maindoc/UBL-eSPap-Invoice-2.1.xsd')
        else
          ubl_version = doc.xpath('//cbc:UBLVersionID', cbc: "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2").text
          if ubl_version.nil? or ubl_version == ''
            standard_path(namespace)
          else
            standard_path("#{namespace}_ubl#{ubl_version}")
          end
        end
      when CII_DOCUMENT
        customization_id = doc.xpath('//ram:GuidelineSpecifiedDocumentContextParameter/ram:ID', ram: RAM).text
        case customization_id
        when 'urn:factur-x.eu:1p0:minimum'
          schema_path('factur-x/minimum/FACTUR-X_MINIMUM.xsd')
        when 'urn:cen.eu:en16931:2017'
          schema_path('factur-x/en16931/FACTUR-X_EN16931.xsd')
        when 'urn:cen.eu:en16931:2017#compliant#urn:factur-x.eu:1p0:basic'
          schema_path('factur-x/basic/FACTUR-X_BASIC.xsd')
        when 'urn:factur-x.eu:1p0:basicwl'
          schema_path('factur-x/basic_wl/FACTUR-X_BASIC-WL.xsd')
        when 'urn:cen.eu:en16931:2017#conformant#urn:factur-x.eu:1p0:extended'
          schema_path('factur-x/extended/FACTUR-X_EXTENDED.xsd')
        else
          standard_path(namespace)
        end
      else
        ubl_version = doc.xpath('//cbc:UBLVersionID', cbc: "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2").text
        if ubl_version.nil? or ubl_version == ''
          standard_path(namespace)
        else
          standard_path("#{namespace}_ubl#{ubl_version}")
        end
      end
    end

    # Setup symlinks from xmlns to shcemas
    def self.symlink
      symlinks = {}
      Dir.chdir('lib/xsd/schemas/') do
        Dir["**/*.xsd"].each do |xsdname|
          doc = Nokogiri::XML(File.read(schema_path(xsdname)))
          if doc.root['targetNamespace']
            xmlns = doc.root['targetNamespace']
            if xmlns =~ UBL_DOCUMENT and doc.root['version']
              if doc.root['version'] == '2.1'
                # add extra link without _ubl2.1 suffix to use it as default
                symlinks[xmlns] = xsdname
              end
              # ubl 2.0 & 2.1 share the same targetNamespace, we add version
              xmlns = "#{xmlns}_ubl#{doc.root['version']}"
            end
          else
            xmlns = doc.namespaces['xmlns']
            if xmlns == 'http://www.w3.org/2001/XMLSchema'
              xmlns = doc.namespaces.to_a[1][1]
            end
          end
          symlinks[xmlns] = xsdname
        end
      end
      Dir.chdir('lib/xsd/xmlns/') do
        symlinks.each do |to, from|
          begin
            from = "../schemas/#{from}"
            to = normalize_xmlns(to)
            File.symlink(from, to)
          rescue Errno::EEXIST, TypeError
            # already exists or nil
          else
            puts "#{from} -> #{to}"
          end
        end
      end
    end

    private

    def schema_path(xsdname)
      Validator.schema_path(xsdname)
    end

    def self.normalize_xmlns(xmlns)
      xmlns.gsub(/[^\w_\-\.#]+/,'_') rescue nil
    end

    def self.schema_path(xsdname)
      File.expand_path("../schemas/#{xsdname}", __FILE__)
    end

    def standard_path(namespace)
      xmlns_path ||= File.expand_path("../xmlns/#{Validator.normalize_xmlns(namespace)}", __FILE__)
      if File.exists?(xmlns_path)
        File.realdirpath(xmlns_path)
      else
        raise StandardError.new("Unknown namespace #{namespace}")
      end
    end
  end
end
