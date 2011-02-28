class Membership < ActiveRecord::Base
  belongs_to :person
  belongs_to :group

  #No duplicate memberships, please
  validates_uniqueness_of :person_id, :scope => :group_id
  
  acts_as_list  :scope => :person

  scope :active, where("end_date is ?", nil)

end