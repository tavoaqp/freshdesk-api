require 'rest_client'
require 'nokogiri'

class Freshdesk

  # custom errors
  class AlreadyExistedError < StandardError; end
  class ConnectionError < StandardError; end
  
  attr_accessor :base_url
  
  def initialize(base_url, username, password)
    
    @base_url = base_url
    
    RestClient.add_before_execution_proc do | req, params |
      req.basic_auth username, password
    end
  end
  
  # Freshdesk API client support "GET" with id parameter optional
  #   Returns nil if there is no response
  def self.define_get(name, *args)
    name = name.to_s
    method_name = "get_" + name

    define_method method_name do |*args| 
      args = args[0] if args.class==Array
      uri = mapping(name)
      uri.gsub!(/.xml/, "/#{args[:id]}.xml") if !args.nil? && !args[:id].nil?
      uri.gsub!(/.xml/, ".xml?#{args[:query].to_query}") if !args.nil? && !args[:query].nil?
      begin
        response = RestClient.get uri

        # RAILS DOESN'T ACCEPT YAML
        response.gsub!("type=\"yaml\"","")

        doc = Nokogiri::XML.parse(response)
        doc.xpath('//'+doc_name(name)).map do |i|
          Hash.from_xml(i.to_s)[hash_name(name)]
        end
      
      rescue Exception
        nil
      end
    end
  end
  
  # Freshdesk API client support "DELETE" with the required id parameter
  def self.define_delete(name, *args)
    name = name.to_s
    method_name = "delete_" + name

    define_method method_name do |args|
      args = args[0] if args.class==Array
      uri = mapping(name)
      raise StandardError, "An ID is required to delete" if args.nil? || args[:id].nil?
      uri.gsub!(/.xml/, "/#{args[:id]}.xml")
      RestClient.delete uri
    end
  end
  
  # Freshdesk API client support "POST" with the optional key, value parameter
  #
  #  Will throw: 
  #    AlreadyExistedError if there is exact copy of data in the server
  #    ConnectionError     if there is connection problem with the server
  def self.define_post(name, *args)
    name = name.to_s
    method_name = "post_" + name
    
    define_method method_name do |args|
      args = args[0] if args.class==Array

      uri = mapping(name)
      builder = Nokogiri::XML::Builder.new do |xml|
        xml.send(doc_name(name)) {
          args.each do |key, value|
            xml.send(key, value)
          end
        }
      end
      begin
        response = RestClient.post uri, builder.to_xml, :content_type => "text/xml", :accept => "text/xml"

        # RAILS DOESN'T ACCEPT YAML
        response.gsub!("type=\"yaml\"","")

        doc = Nokogiri::XML.parse(response)
        Hash.from_xml(response)[hash_name(name)]

      rescue RestClient::UnprocessableEntity
        raise AlreadyExistedError, "Entry already existed"
      
      rescue RestClient::InternalServerError
        raise ConnectionError, "Connection to the server failed. Please check hostname"
      
      rescue RestClient::Found
        raise ConnectionError, "Connection to the server failed. Please check username/password"
      
      rescue Exception => e3
        raise
      end   
       
    end
  end

  # Freshdesk API client support "PUT" with key, value parameter
  #
  #  Will throw: 
  #    ConnectionError     if there is connection problem with the server
  def self.define_put(name, *args)
    name = name.to_s
    method_name = "put_" + name
    
    define_method method_name do |args|
      args = args[0] if args.class==Array
      raise StandardError, "id is required to modify data"  if args.nil? || args[:id].nil?
      uri = mapping(name)
      builder = Nokogiri::XML::Builder.new do |xml|
        xml.send(doc_name(name)) {
          args.each do |key, value|
            xml.send(key, value)
          end
        }
      end

      begin 
        uri.gsub!(/.xml/, "/#{args[:id]}.xml")
        response = RestClient.put uri, builder.to_xml, :content_type => "text/xml"
        
      rescue RestClient::InternalServerError
        raise ConnectionError, "Connection to the server failed. Please check hostname"
      
      rescue RestClient::Found
        raise ConnectionError, "Connection to the server failed. Please check username/password"
      
      rescue Exception => e3
        raise
      end   
      
      response   
    end
  end
  
  [:user_tickets, :tickets, :ticket_fields, :users, :forums, :solutions, :companies].each do |a|
    define_get a
    define_post a  
    define_delete a
    define_put a
  end
  
   
  # Mapping of object name to url:
  #   tickets => helpdesk/tickets.xml
  #   ticket_fields => /ticket_fields.xml
  #   users => /contacts.xml
  #   forums => /categories.xml
  #   solutions => /solution/categories.xml
  #   companies => /customers.xml
  def mapping(method_name)
    path = case method_name
      when "tickets" then File.join(@base_url, "helpdesk/tickets.xml")
      when "user_tickets" then File.join(@base_url, "helpdesk/tickets.xml")
      when "ticket_fields" then File.join( @base_url, "ticket_fields.xml")
      when "users" then File.join(@base_url, "contacts.xml")
      when "forums" then File.join(@base_url, "categories.xml")
      when "solutions" then File.join(@base_url, "solution/categories.xml")
      when "companies" then File.join(@base_url, "customers.xml")
    end
  end
  
  # match with the root name of xml document that freskdesk uses
  def doc_name(name)
    doc = case name 
      when "user_tickets" then "helpdesk-ticket"
      when "tickets" then "helpdesk-ticket"
      when "ticket_fields" then "helpdesk-ticket-fields"
      when "users" then "user"
      when "companies" then "customer"
      else raise StandardError, "No root object for this call"
    end
  end
  # match with the name with the hash name
  def hash_name(name)
    doc = case name 
      when "user_tickets" then "helpdesk_ticket"
      when "tickets" then "helpdesk_ticket"
      when "ticket_fields" then "helpdesk_ticket_fields"
      else doc_name(name)
    end
  end
end

