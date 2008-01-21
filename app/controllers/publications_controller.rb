class PublicationsController < ApplicationController

  make_resourceful do 
    build :index, :show
    
    publish :yaml, :xml, :json, :attributes => [
      :id, :name, :url, :issn_isbn, :publisher_id, {
        :publisher => [:id, :name]
        }
      ]
    
    before :index do
      if params[:q]
        query = params[:q]
        @current_objects = current_objects
      else
        @current_objects = Publication.paginate(
          :all,
          :conditions => ["id = authority_id"],
          :order => "name",
          :page => params[:page] || 1,
          :per_page => 20
        )
      end      
    end
    
    before :show do      
      @citations = Citation.paginate(
        :all,
        :conditions => ["publication_id = ? and citation_state_id = ?", current_object.id, 3],
        :order => "year DESC, title_primary",
        :page => params[:page] || 1,
        :per_page => 10
      )
      
      @authority_for = Publication.find(
        :all,
        :conditions => ["authority_id = ?", current_object.id],
        :order => "name"
      )
    end
  end
  
  private
  def current_objects
    @current_objects ||= current_model.find_all_by_issn_isbn(params[:q])
  end
end