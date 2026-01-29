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
        }
    }
}
