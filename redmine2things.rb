require 'i18n/en'

# for working with Things
require 'osx/cocoa'
include OSX
OSX.require_framework 'ScriptingBridge'

# for working with redmine
require 'rubygems'
require 'active_resource'

# for issues fetching from redmine
class Issue < ActiveResource::Base
end

class Redmine2Things
  
  def initialize(redmine_params, things_params)
    @redmine_params = redmine_params
    @things_params  = things_params
    
    @redmine_params[:site] = @redmine_params[:site]
    @redmine_params[:project_url_prefix] = @redmine_params[:site] + '/projects/'
    @redmine_params[:task_url_prefix]    = @redmine_params[:site] + '/issues/'

    # put or not debug information in stdout
    @trace_execution = true
    
    # Things application
    @things  = OSX::SBApplication.applicationWithBundleIdentifier_("com.culturedcode.Things")
  end
  
  # Puts dubug information in stdout
  def log(message)
    puts message if (@trace_execution)
  end
  
  # Create projects and tasks hash arrays, which were imported from redmine to Things earlier
  def load_things_data()
    # находим проекты с id проектов в redmine и заносим их в хеш-массив
    @things_projects_hash = {}
    @things_archive_projects_hash = {}
    @things_todos_hash = {}  
    
    projectRegexp = Regexp.new('(' + @redmine_params[:project_url_prefix].gsub('/', '\/') + '[-\w\d]+)')
    todoRegexp    = Regexp.new('(' + @redmine_params[:task_url_prefix].gsub('/', '\/') + '\d+)')
    
    # Load projects (completed/not completed) and tasks
    @things.projects.each do |project|      
      ids = project.notes.scan(projectRegexp)
      if (ids.size > 0 && ids[0].size > 0)
        if (project.completionDate.nil?)
          @things_projects_hash[ids[0][0].to_sym] = project 
          project.toDos.each do |todo|
            todo_ids = todo.notes.scan(todoRegexp)          
            @things_todos_hash[todo_ids[0][0].to_sym] = todo if (todo_ids.size > 0 && todo_ids[0].size > 0)
          end
        else
          @things_archive_projects_hash[ids[0][0].to_sym] = project 
        end
      end
    end
    
    @things_working_area = nil
    if (@things_params.key?(:area))
      @things.areas.each { |area| @things_working_area = area if (area.name == @things_params[:area]) }
    end
  end
  
  # Load issues from redmine via API
  def load_redmine_data()
    Issue.site = @redmine_params[:site]
    Issue.user = @redmine_params[:user]
    Issue.password = @redmine_params[:password]
    
    @issues = Issue.find(:all, :params => { :assigned_to_id => @redmine_params[:user_id] })
  end
  
  def update_to_do_properties(todo, issue)
    todo.name = issue.subject
    todo.dueDate = issue.due_date if (!issue.due_date.nil?)
    todo.notes = '[url=' + @redmine_params[:task_url_prefix] + issue.id + '] ' + $r2b_messages[:task_in_redmine] + ' [/url]'
    
    tags = [issue.tracker.name]
    if (issue.estimated_hours.to_f > 0)
      if (issue.estimated_hours.to_f < 1)
        tags.push((issue.estimated_hours.to_f * 60).to_i.to_s + ' ' + $r2b_messages[:min])
      else
        h = issue.estimated_hours.to_i
        tags.push(h.to_s + ' ' + (h < 5 ? (h == 1 ? $r2b_messages[:hour1] : $r2b_messages[:hour2]) : $r2b_messages[:hour3]))
      end
    end
    todo.tagNames = tags.join(', ')
  end
  
  def sync_tasks()
    self.log('')
    self.log('check and create tasks')
    self.log('-------------------------')

    @issues.each do |issue|      
      todo_id = (@redmine_params[:task_url_prefix] + issue.id).to_sym
      if (!@things_todos_hash.key?(todo_id))
        #находим или создаем проект под задачу
        project_id = (@redmine_params[:project_url_prefix] + issue.project.id).to_sym

        if (@things_projects_hash.key?(project_id))          
          #adding new task
          new_todo = OSX::ThingsToDo.new
          @things_projects_hash[project_id].toDos.unshift(new_todo)
  
          # set properties
          self.update_to_do_properties(new_todo, issue)
  
          # Move to Today list
          new_todo.moveTo(@things.lists[1])        
          
          self.log('Task ' + issue.subject + ' was added to project ' + issue.project.name)          
        elsif (@things_archive_projects_hash.key?(project_id))
          self.log('Project "' + issue.project.name + '" for task "' + issue.subject + '" in Logbook. Don\'t add task to Things');
        else
          self.log('Ops! Project "' + issue.project.name + '" for task "' + issue.subject + '" not found');
        end        
      else
        self.log('Task ' + issue.subject + ' was found')
      end      
    end    
  end
  
  def sync_projects
    self.log('')
    self.log('check and create projects')
    self.log('-------------------------')
    
    prev_project_id = -1
    @issues.each do |issue|      
      if (issue.project.id != prev_project_id)
        project_id = (@redmine_params[:project_url_prefix] + issue.project.id).to_sym
        
        # not founded in Things
        if (!@things_projects_hash.key?(project_id) && !@things_archive_projects_hash.key?(project_id))
          project = OSX::ThingsProject.new
          if (!@things_working_area.nil?)  
            @things_working_area.toDos.push(project) 
          else
            @things.projects.push(project)        
          end
          
          project.name = issue.project.name.to_s
          project.notes = '[url=' + project_id.to_s + '] ' + $r2b_messages[:project_in_redmine] + ' [/url]'
          if (@things_params.key?(:tags))  
            project.tagNames = @things_params[:tags]
          end
          
          @things_projects_hash[project_id] = project
          self.log('Project ' + issue.project.name + ' was created')
        else
          self.log('Project ' + issue.project.name + ' was found')
        end
                
        prev_project_id = issue.project.id
      end
    end
  end
  
  def sync()
    @things.emptyTrash

    self.load_things_data
    self.load_redmine_data
    self.sync_projects
    self.sync_tasks
    
    @things.logCompletedNow    
  end

end
