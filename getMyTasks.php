<?php
  /*
   * Отдает текущие задачи пользователя
   *
   */
   
  $config = array(
                   //данные для доступа к БД
                   'dbserver' =>      'localhost',
                   'username' =>      'username',
                   'password' =>      'password',
                   'database' =>      'dbname',
                 );

  header('Content-Type: text/plain; charset=utf-8');

  $conn = mysql_connect($config['dbserver'], $config['username'], $config['password']);
  if (!$conn) exit;
    
  if (!mysql_select_db($config['database'])) exit;

  $username = addslashes($_GET['username']);
  $passwordSha1 = addslashes($_GET['p']);
  
  mysql_query('SET NAMES utf8');
    
  //выбираем всех незаблокированных и активированных пользователей
  $query = 'SELECT id, login, hashed_password FROM users WHERE status <> 2 AND status <> 3 AND login ="' . $username . '"';
  $result = mysql_query($query);

  if (!$result) exit;
  $r = mysql_fetch_assoc($result);  
  mysql_free_result($result);    

  if ($r['hashed_password'] != $passwordSha1) exit;
  $userId = $r['id'];
  
  
  //вытаскиваем проекты пользователя
  $query = 'SELECT p.id, p.name, p.identifier FROM members m, projects p WHERE m.project_id = p.id' .
           ' AND m.user_id = "' . $userId . '"';
  $result = mysql_query($query);  
  if (!$result) exit;
  
  $projects = array();
  while ($projects[] = mysql_fetch_assoc($result));
  
  foreach($projects as &$project)
  {
    $query = 'SELECT i.id, i.subject, i.due_date, i.description, i.status_id, i.estimated_hours, t.name as type' . 
             ' FROM issues i, trackers t WHERE i.tracker_id=t.id AND project_id = ' . $project['id'] .
             ' AND assigned_to_id = "' . $userId . '" AND status_id NOT IN (5, 11, 12)';
    $result = mysql_query($query);  
    if ($result)
    {
      $s[] = 'THINGS';
      while ($row = mysql_fetch_assoc($result))
        echo $row['id'] . '||' . $row['subject'] . '||' . (!empty($row['due_date']) ? date('d.m.Y', strtotime($row['due_date'])) : '') . '||' . 
             $row['estimated_hours'] . '||' . $project['identifier'] . '||' . $project['name'] . '||' . $row['type'] . "||\n";
    }        
  }
  
  mysql_close($conn);
