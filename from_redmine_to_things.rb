#!/usr/bin/env ruby

require "net/http"
require "osx/cocoa"
include OSX
OSX.require_framework 'ScriptingBridge'

class RedmineToThings
  
  # _baseUrl - базовый адрес, используемый при получении данных из Redmine и формировании ссылок в notes
  # _importFile - файл, который отдает данные из Redmine
  # _separator - разделитель данных в строке
  # _area - область, в которую помещаются новые проекты
  # _projectTags - теги, назначаемые проекту. Перечисляются через запятую
  def initialize(_baseUrl, _importFile, _area, _projectTags, _separator = '||')
    @fName   = _importFile
    @baseUrl = _baseUrl
    
    @area = _area
    @projectTags = _projectTags

    @separator = _separator
    # выводить информационные сообщения при выполнении
    @traceExecution = false
    
    @projectUrlPrefix = 'http://' + @baseUrl + '/projects/'
    @taskUrlPrefix    = 'http://' + @baseUrl + '/issues/'

    @things  = OSX::SBApplication.applicationWithBundleIdentifier_("com.culturedcode.Things")
  end
  
  def log(message)
    puts message if (@traceExecution)
  end
  
  # создаем хеш-массивы проектов и задач, которые пришли из redmine и уже есть в Things
  def loadThingsData
    @things.emptyTrash
    thingsProjects = @things.projects    

    # находим проекты с id проектов в redmine и заносим их в хеш-массив
    @thingsProjectsHash = {}
    @thingsToDosHash = {}

    thingsProjects.each do |project|      
      ids = project.notes.scan(/(http:\/\/redmine\.skillum\.ru\/projects\/(show\/?)[-\w]+)/)
      if (ids.size > 0 && ids[0].size > 0)
        @thingsProjectsHash[ids[0][0].to_s.gsub('show/', '')] = project 
        project.toDos.each do |toDo|
          toDoIds = toDo.notes.scan(/(http:\/\/redmine\.skillum\.ru\/issues\/(show\/?)\d+)/)          
          @thingsToDosHash[toDoIds[0][0].to_s.gsub('show/', '')] = toDo if (toDoIds.size > 0 && toDoIds[0].size > 0)
        end
      end
    end
    
    @thingsIntaroArea = nil
    @things.areas.each { |area| @thingsIntaroArea = area if (area.name == @area) }
  end
  
  def updateToDoProperties(toDo, data)
    toDo.name = data[1]
    toDo.dueDate = data[2] if (data[2].size > 0)
    toDo.notes = '[url=' + @taskUrlPrefix + data[0] + '] Задача в Redmine [/url]'
    
    tags = [data[6]]
    if (data[3].to_f > 0)
      if (data[3].to_f < 1)
        tags.push((data[3].to_f * 60).to_i.to_s + ' мин')
      else
        h = data[3].to_i
        tags.push(h.to_s + ' час' + (h < 5 ? 'а' : 'ов'))
      end
    end
    toDo.tagNames = tags.join(', ')
    self.log('Назначены теги: ' + toDo.tagNames)
  end
  
  def export
    self.loadThingsData
    
    data = Net::HTTP.get(@baseUrl, @fName)
    
    # сначала обновляем существующие задачи и заносим те, для которых уже есть проекты в Things
    data.each do |line|
      thingArray = line.split(@separator)
      
    toDoId = @taskUrlPrefix + thingArray[0]
    if (@thingsToDosHash.key?(toDoId))
      self.log(' ')
      self.log('Задача ' + thingArray[1].to_s + ' существует')
      self.log('----')
    else
      if (thingArray[4])
        #находим или создаем проект под задачу
        projectId = @projectUrlPrefix + thingArray[4] 
         
        self.log(' ')
        self.log('Заносим в ' + projectId + ' задачу ' + thingArray[1].to_s)
        self.log('----')
        
        if (@thingsProjectsHash.key?(projectId))
          project = @thingsProjectsHash[projectId]
          self.log(project.name + ' найден')
        
          newToDo = OSX::ThingsToDo.new
          project.toDos.unshift(newToDo)
  
          # устанавливаем свойства
          self.updateToDoProperties(newToDo, thingArray)

          # кладем в сегодня
          newToDo.moveTo(@things.lists[1])
        end        
      end          
    end
      
    end

    # теперь заносим те, для которых нужно создать проекты в Things
    data.each do |line|
      thingArray = line.split(@separator)
      
      toDoId = @taskUrlPrefix + thingArray[0]
      if (!@thingsToDosHash.key?(toDoId))
        #находим или создаем проект под задачу
        projectId = @projectUrlPrefix + thingArray[4]
        
        self.log(' ')
        self.log('Заносим в ' + projectId + ' задачу ' + thingArray[1].to_s)
        self.log('----')
        
        if (!@thingsProjectsHash.key?(projectId))
          project = OSX::ThingsProject.new
          if (!@thingsIntaroArea.nil?)  
            @thingsIntaroArea.toDos.push(project) 
          else
            @things.projects.push(project)        
          end
          
          project.name = thingArray[5].to_s
          project.notes = '[url=' + projectId + '] Проект в Redmine [/url]'
          project.tagNames = @projectTags
          
          @thingsProjectsHash[projectId] = project
          self.log(project.name + ' создан')
        
          #задачи нет в Things
          newToDo = OSX::ThingsToDo.new
          project.toDos.unshift(newToDo)
  
          # устанавливаем свойства
          self.updateToDoProperties(newToDo, thingArray)

          # кладем в сегодня
          newToDo.moveTo(@things.lists[1])
        end
        
      end
      
    end
    
    @things.logCompletedNow
    
  end

end

# запускаем экспорт
rtt = RedmineToThings.new("redmine.skillum.ru", 
                          "/getMyTasks.php?username=muxx&p=ad6e916ddeb947e35a547c759f647731c32dbe16",
                          "Работа", "Работа")
rtt.export
