pipeline {
    agent any

    stages {
        stage('Build Artifacts') {
            steps {
                sh "mvn clean package -DskipTests=true"
                archive 'target/*.jar'
            }
        }

        stage('Unit tests') {
            steps {
                sh "mvn test"
            }
            post {
                always {
                    junit 'target/surefire-reports/*.xml'
                    jacoco execPattern: 'target/jacoco.exec'
                }
            }
        }

        stage('Docker Build and Push') {
            steps {
                withDockerRegistry([credentialsId: "docker-hub", url: ""]) {
                    sh "printenv"
                    sh "docker images"
                    sh 'docker build -t kunal70223/numeric-app:""$GIT_COMMIT"" .'
                    sh 'docker push kunal70223/numeric-app:""$GIT_COMMIT""'
                }
            }
        }
    }
}
