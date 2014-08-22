# Based on ORCID Message 1.1 for Works
xml.tag!('orcid-work', 'visibility' => "public") do
  xml.tag!('work-title') do
    xml.title(h(work.title_primary))
    xml.subtitle(h(work.title_secondary)) if work.title_secondary.present?
  end
  xml.tag!('journal-title', (work.publication.name)) if work.publication_id.present?
  if work.abstract.present?
    abstract = work.abstract.gsub(/[\r\n]/,' ')
    xml.tag!('short-description', h(abstract))
  end
#   xml.tag!('work-citation') do
#     xml.tag!('work-citation-type', "formatted-apa")
#     xml.citation(h(apa)) unless apa.nil?
#   end
  xml.tag!('work-citation') do
    xml.tag!('work-citation-type', "bibtex")
    bibtex = export.drive_csl('bibtex', work).strip
    xml.citation(h(bibtex)) unless bibtex.nil?
  end  
  xml.tag!('work-type', to_orcid_type(work))
  if work.year.present?
    # year required to use publication-date
		xml.tag!('publication-date') do
			xml.year(h(work.year))
			# month and day optional
			if work.publication_date_month.present?
			  xml.month(h(Date.strptime(work.publication_date_month.to_s, '%m').strftime('%m')))
      end
		end
	end
	if work.links.present?
	  xml.tag!('work-external-identifiers') do
	    split_potential_links(work).each do |link|
	      if doi = looks_like_doi(link)
	        xml.tag!('work-external-identifier') do
	          xml.tag!('work-external-identifier-type', "doi")
	          xml.tag!('work-external-identifier-id', doi)
	        end
	      elsif pmid = looks_like_pmid(link)
	        xml.tag!('work-external-identifier') do
	          xml.tag!('work-external-identifier-type', "pmid")
	          xml.tag!('work-external-identifier-id', pmid)
	        end
	      end
	    end
	end  
  xml.tag!('work-contributors') do
		if work.authors.present?
		  work.authors.each_with_index do |a, i|
  		  xml.contributor do
  		    xml.tag!('credit-name', a[:name])
  		    xml.tag!('contributor-attributes') do
						xml.tag!('contributor-sequence', i == 0? "first" : "additional")
						xml.tag!('contributor-role', "author")
  		    end
  		  end
			end
		end
	end
	end
	xml.tag!('language-code', "en")
end