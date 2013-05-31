#-- encoding: UTF-8
#-- copyright
# OpenProject is a project management system.
#
# Copyright (C) 2012-2013 the OpenProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# See doc/COPYRIGHT.rdoc for more details.
#++

module Redmine::MenuManager::MenuHelper
  include ::Redmine::MenuManager::TopMenuHelper
  include AccessibilityHelper

  # Returns the current menu item name
  def current_menu_item
    controller.current_menu_item
  end

  # Renders the application main menu
  def render_main_menu(project)
    build_wiki_menus(project) if project
    render_menu((project && !project.new_record?) ? :project_menu : :application_menu, project)
  end

  def build_wiki_menus(project)
    project_wiki = project.wiki

    WikiMenuItem.main_items(project_wiki).each do |main_item|
      Redmine::MenuManager.loose :project_menu do |menu|
        menu.push "#{main_item.item_class}".to_sym,
          { :controller => '/wiki', :action => 'show', :id => h(main_item.title) },
            :param => :project_id, :caption => main_item.name

        menu.push :"#{main_item.item_class}_new_page", {:action=>"new_child", :controller=>"/wiki", :id => h(main_item.title) },
          :param => :project_id, :caption => :create_child_page,
          :parent => "#{main_item.item_class}".to_sym if main_item.new_wiki_page and
            WikiPage.find_by_wiki_id_and_title(project_wiki.id, main_item.title)

        menu.push :"#{main_item.item_class}_toc", {:action => 'index', :controller => '/wiki', :id => h(main_item.title)}, :param => :project_id, :caption => :label_table_of_contents, :parent => "#{main_item.item_class}".to_sym if main_item.index_page

        main_item.children.each do |child|
          menu.push "#{child.item_class}".to_sym,
            { :controller => '/wiki', :action => 'show', :id => h(child.title) },
              :param => :project_id, :caption => child.name, :parent => "#{main_item.item_class}".to_sym
        end
      end
    end
  end

  def display_main_menu?(project)
    menu_name = project && !project.new_record? ? :project_menu : :application_menu
    Redmine::MenuManager.items(menu_name).size > 1 # 1 element is the root
  end

  def render_menu(menu, locals = {})
    # support both the old and the new signature
    # old: (menu, project=nil)
    project = locals.is_a?(Project) || locals.nil? ?
                locals :
                locals[:project]

    links = menu_items_for(menu, project).map do |node|
      render_menu_node(node, locals)
    end

    links.empty? ? nil : content_tag('ul', links.join("\n").html_safe, :class => "menu_root")
  end

  def render_action_menu(menu, locals = {})
    # support both the old and the new signature
    # old: (menu, project=nil)
    project = locals.is_a?(Project) ?
                locals :
                locals[:project]

    links = menu_items_for(menu, project).map do |node|
      render_menu_node(node, locals)
    end

    links.empty? ? nil : content_tag('ul', links.join("\n").html_safe, :class => "menu_root action_menu_main")
  end

  def render_drop_down_menu_node(label, items_or_options_with_block = nil, html_options = {}, &block)

    items, options = if block_given?
                       [[], items_or_options_with_block || {} ]
                     else
                       [items_or_options_with_block, html_options]
                     end

    return "" if items.empty? && !block_given?

    options.reverse_merge!({ :class => "drop-down" })

    content_tag :li, options do
      label + if block_given?
                yield
              else
                content_tag :ul, :style => "display:none" do

                  items.collect do |item|
                    render_menu_node(item)
                  end.join(" ").html_safe
                end
              end
    end
  end

  def render_menu_node(node, locals = {})
    # support both the old and the new interface
    project, locals = locals.is_a?(Project) ?
                        [project, locals] :
                        [locals[:project], locals]

    return "" if project and not allowed_node?(node, User.current, project)

    if node.has_children? || !node.child_menus.nil?
      render_menu_node_with_children(node, locals)
    else
      caption, url, selected = extract_node_details(node, locals)

      content_tag('li', render_single_menu_node(node, caption, url, selected, locals))
    end
  end

  def render_menu_node_with_children(node, locals = {})
    # support both the old and the new interface
    project = locals.is_a?(Project) ?
                locals :
                locals[:project]

    caption, url, selected = extract_node_details(node, locals)

    content_tag :li do
      # Standard children
      standard_children_list = node.children.collect do |child|
                                 render_menu_node(child, locals)
                               end.join.html_safe

      # Unattached children
      unattached_children_list = render_unattached_children_menu(node, locals)

      # Parent
      node = [render_single_menu_node(node, caption, url, selected, locals)]

      # add children
      node << content_tag(:ul, standard_children_list, :class => 'menu-children') unless standard_children_list.empty?
      node << content_tag(:ul, unattached_children_list, :class => 'menu-children unattached') unless unattached_children_list.blank?

      node.join("\n").html_safe
    end
  end

  # Returns a list of unattached children menu items
  def render_unattached_children_menu(node, project)
    return nil unless node.child_menus

    "".tap do |child_html|
      unattached_children = node.child_menus.call(project)
      # Tree nodes support #each so we need to do object detection
      if unattached_children.is_a? Array
        unattached_children.each do |child|
          child_html << content_tag(:li, render_unattached_menu_item(child, project))
        end
      else
        raise Redmine::MenuManager::MenuError, ":child_menus must be an array of MenuItems"
      end
    end.html_safe
  end

  def render_single_menu_node(item, caption, url, selected, locals)
    link_text    = you_are_here_info(selected) + caption

    if item.block
      item.block.call locals
    else

      html_options = item.html_options(:selected => selected)
      html_options[:title] = caption

      link_to link_text, url, html_options
    end
  end

  def render_unattached_menu_item(menu_item, project)
    raise Redmine::MenuManager::MenuError, ":child_menus must be an array of MenuItems" unless menu_item.is_a? Redmine::MenuManager::MenuItem

    if User.current.allowed_to?(menu_item.url, project)
      link_to(h(menu_item.caption),
              menu_item.url,
              menu_item.html_options)
    end
  end

  def menu_items_for(menu, project=nil)
    items = []

    # TODO: have an explicit method for querying for undefined menus
    if Redmine::MenuManager.items(menu).children.size == 0
      file = Rails.root.join("app/widgets/menus/#{menu}.rb")

      require Rails.root.join("app/widgets/menus/#{menu}") if File.exists?(file)
    end

    Redmine::MenuManager.items(menu).root.children.each do |node|
      if allowed_node?(node, User.current, project)
        if block_given?
          yield node
        else
          items << node  # TODO: not used?
        end
      end
    end
    return block_given? ? nil : items
  end

  def extract_node_details(node, locals = {})
    # support both the old and the new signature
    # old: (menu, project=nil)
    project = locals.is_a?(Project) || locals.nil? ?
                locals :
                locals[:project]

    locals = { :project => locals } if locals.is_a?(Project)

    item = node
    url = case item.url
    when Hash
      item.url.inject({}) do |h, (k, v)|
        h[k] = if locals.has_key?(v) && locals[v].is_a?(ActiveRecord::Base)
                 locals[v].id
               else
                 v
               end

        h
      end
      #project.nil? ? item.url : {item.param => project}.merge(item.url)
    when Symbol
      send(item.url)
    else
      item.url
    end
    caption = item.caption(project)

    selected = current_menu_item == item.name

    return [caption, url, selected]
  end

  # Checks if a user is allowed to access the menu item by:
  #
  # * Checking the conditions of the item
  # * Checking the url target (project only)
  def allowed_node?(node, user, project)
    if node.condition && !node.condition.call(project)
      # Condition that doesn't pass
      return false
    end

    # TODO: get a better mechanism
    if node.block
      return true
    end

    if node.url.empty?
      return true
    end

    if project
      return user && user.allowed_to?(node.url, project)
    else
      # outside a project, all menu items allowed
      return true
    end
  end
end
